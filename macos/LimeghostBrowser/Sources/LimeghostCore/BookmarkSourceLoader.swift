import Foundation

// Moved here from the Mac's `BookmarkImportSources.swift` on September 29,
// 2026, when the iPhone gained Import Bookmarks. Reading a chosen file and
// naming the folder it lands in touch nothing but Foundation, so they belong
// to Core, and both apps now say the same sentence when a file will not read.
// What stayed behind is the Mac's own part: finding other browsers' profiles
// on its disk.

/// The destination folder's name: "Imported from Chrome — 21 August 2026".
/// One new top-level folder holds an entire import, preserving the source's
/// own structure beneath it — Limeghost never merges an import into a
/// folder that already exists.
public enum BookmarkImportFolderNaming {
    public static func destinationFolderTitle(sourceLabel: String, date: Date = Date()) -> String {
        "Imported from \(sourceLabel) — \(formatted(date))"
    }

    /// Fixed to `en_US_POSIX` so the month name is always English and the
    /// day-month-year order never depends on the machine's own region
    /// settings — the same folder name regardless of who is reading it.
    private static func formatted(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "d MMMM yyyy"
        return formatter.string(from: date)
    }
}

/// Turns a chosen bookmarks file into a `BookmarkImport`, and turns whatever
/// goes wrong along the way into a sentence a person can act on rather than
/// a parser exception.
public enum BookmarkSourceLoader {
    public struct Loaded {
        public let imported: BookmarkImport
        /// Entries the source held that could not be kept — an unsafe or
        /// missing address, most often — counted so the final report can be
        /// honest about them instead of letting them vanish silently.
        public let unusableCount: Int
    }

    /// Not `Result<Loaded, Error>`: every failure here is already a plain,
    /// finished sentence for a person to read, never a raw parser exception
    /// a view would have to translate.
    public enum Outcome {
        case success(Loaded)
        case failure(String)
    }

    public static func load(from url: URL) -> Outcome {
        guard let data = try? Data(contentsOf: url) else {
            return .failure("Limeghost couldn't open that file.")
        }
        return load(data)
    }

    /// Exposed separately from `load(from:)` so a caller that already has
    /// the bytes — Safari's plist read, for instance — is not made to write
    /// them back out just to read them again.
    public static func load(_ data: Data) -> Outcome {
        // A ZIP archive is named for what it is, and nothing inside it is
        // read. Safari on the iPhone exports one holding the bookmarks file
        // beside the passwords, unencrypted; the person unpacks it and
        // chooses the bookmarks file alone. Before this check an archive
        // whose entries were stored uncompressed was read as bookmarks.
        if data.starts(with: [0x50, 0x4B, 0x03, 0x04]) {
            return .failure(
                "That's a ZIP archive, not the bookmarks file itself. Open it to unpack it, "
                + "then choose the bookmarks HTML file inside."
            )
        }
        switch sniffFormat(data) {
        case .chromiumJSON:
            return parseChromium(data)
        case .netscapeHTML:
            return parseNetscape(data)
        case .unknown:
            // The sniff is a peek, not a verdict — a real attempt still runs
            // before this gives up honestly.
            switch parseChromium(data) {
            case .success(let loaded): return .success(loaded)
            case .failure:
                switch parseNetscape(data) {
                case .success(let loaded): return .success(loaded)
                case .failure:
                    return .failure(
                        "That file doesn't look like a bookmarks export Limeghost recognizes. In your "
                        + "other browser, look for an option like Export Bookmarks — usually saved as an "
                        + "HTML file — and choose that file here."
                    )
                }
            }
        }
    }

    private enum SniffedFormat { case chromiumJSON, netscapeHTML, unknown }

    private static func sniffFormat(_ data: Data) -> SniffedFormat {
        guard let text = String(data: data.prefix(4096), encoding: .utf8) else { return .unknown }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("{") { return .chromiumJSON }
        if trimmed.range(of: "<dl", options: [.caseInsensitive]) != nil { return .netscapeHTML }
        return .unknown
    }

    private static func parseChromium(_ data: Data) -> Outcome {
        do {
            let imported = try ChromiumBookmarkImporter.parse(data)
            return .success(Loaded(imported: imported, unusableCount: unusableChromiumEntryCount(in: data, usable: imported.bookmarkCount)))
        } catch {
            return .failure(friendlyMessage(for: error))
        }
    }

    private static func parseNetscape(_ data: Data) -> Outcome {
        guard let html = String(data: data, encoding: .utf8) else {
            return .failure("Limeghost couldn't read that file as text.")
        }
        do {
            let imported = try NetscapeBookmarkImporter.parse(html)
            return .success(Loaded(imported: imported, unusableCount: unusableAnchorCount(in: html, usable: imported.bookmarkCount)))
        } catch {
            return .failure(friendlyMessage(for: error))
        }
    }

    private static func friendlyMessage(for error: Error) -> String {
        guard let importError = error as? BookmarkImportError else {
            return "Limeghost couldn't read that file."
        }
        switch importError {
        case .malformedJSON, .truncatedHTML:
            return "That file looks like it was cut off or damaged partway through. Try exporting it again."
        case .missingRoots, .notNetscapeDocument:
            return "That file doesn't look like a bookmarks export Limeghost recognizes."
        case .nestingTooDeep:
            return "That file's folders are nested far deeper than any real bookmarks file — Limeghost stopped reading it to stay safe."
        }
    }

    /// Counts every JSON node shaped like a bookmark (`"type": "url"`) in the
    /// raw file, regardless of whether its address was safe to keep. Exact,
    /// not a guess: Chromium's file is well-formed JSON, so this is a second
    /// structural read rather than a text scan.
    private static func unusableChromiumEntryCount(in data: Data, usable: Int) -> Int {
        guard let object = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) else { return 0 }
        return max(0, countURLNodes(object) - usable)
    }

    private static func countURLNodes(_ value: Any) -> Int {
        if let dictionary = value as? [String: Any] {
            var count = (dictionary["type"] as? String) == "url" ? 1 : 0
            for nested in dictionary.values { count += countURLNodes(nested) }
            return count
        }
        if let array = value as? [Any] {
            return array.reduce(0) { $0 + countURLNodes($1) }
        }
        return 0
    }

    /// A best-effort proxy for Netscape HTML, which has no independent
    /// structured re-parse available: every `<A` tag opening, valid or not.
    /// Clamped so a fuzzy estimate can never report a negative count.
    private static func unusableAnchorCount(in html: String, usable: Int) -> Int {
        max(0, rawAnchorTagCount(in: html) - usable)
    }

    private static func rawAnchorTagCount(in html: String) -> Int {
        var count = 0
        var searchRange = html.startIndex..<html.endIndex
        while let range = html.range(of: "<a", options: [.caseInsensitive], range: searchRange) {
            if range.upperBound < html.endIndex {
                let next = html[range.upperBound]
                if next.isWhitespace || next == ">" { count += 1 }
            } else {
                count += 1
            }
            searchRange = range.upperBound..<html.endIndex
        }
        return count
    }
}
