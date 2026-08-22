import ClearframeCore
import Foundation

/// One place a person could import bookmarks from: a Chromium profile
/// Clearframe found on this Mac, Safari, or a file the person picks
/// themselves. Building this list never reads a bookmarks file — only enough
/// of the filesystem to say what exists and what to call it.
struct DetectedBookmarkSource: Identifiable, Equatable {
    enum Kind: Equatable {
        case chromium
        case safari
        case file
    }

    let id: String
    /// What the source list shows — for a Chromium profile this includes the
    /// profile's own name ("Chrome — Lucian Roman") so choosing among many
    /// profiles is unambiguous.
    let title: String
    let kind: Kind
    /// The `Bookmarks` file to read. `nil` for Safari (permission makes a
    /// direct read unreliable — see `BookmarkImportSourceDiscovery`) and for
    /// "Choose a file…" (there is nothing to read until the person picks
    /// one).
    let bookmarksFileURL: URL?
    /// The plain name used when naming the destination folder — "Chrome",
    /// not "Chrome — Lucian Roman": the profile detail belongs in the source
    /// list, not repeated on every folder it creates.
    let folderNamingLabel: String
}

/// Reads a Chromium `Local State` file for the human-chosen name behind each
/// profile's folder name ("Default", "Profile 1", …). Pure JSON parsing, no
/// filesystem access of its own, so it can be exercised with a synthetic
/// fixture instead of a real profile.
enum ChromiumProfileNaming {
    /// Every display name `Local State` has recorded, keyed by profile
    /// directory name. Missing or malformed input simply yields an empty
    /// map — callers fall back to the directory name themselves.
    static func displayNames(fromLocalState data: Data) -> [String: String] {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let profile = object["profile"] as? [String: Any],
              let infoCache = profile["info_cache"] as? [String: Any] else {
            return [:]
        }
        var result: [String: String] = [:]
        for (directoryName, value) in infoCache {
            guard let entry = value as? [String: Any],
                  let name = (entry["name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !name.isEmpty else { continue }
            result[directoryName] = name
        }
        return result
    }

    /// The label to show for one profile directory: its recorded name when
    /// `Local State` has one, otherwise the directory name itself — "Profile
    /// 1" reads fine on its own when nothing else is known.
    static func displayName(forProfileDirectory directory: String, localState data: Data?) -> String {
        guard let data, let name = displayNames(fromLocalState: data)[directory] else { return directory }
        return name
    }
}

/// Finds the bookmark sources Clearframe can offer without the person typing
/// a path: every Chromium-family profile with a readable `Bookmarks` file,
/// Safari, and the standing "Choose a file…" option.
enum BookmarkImportSourceDiscovery {
    private struct ChromiumBrowser {
        let displayName: String
        /// Relative to Application Support. macOS has no `User Data`
        /// segment — that path component exists only on Windows.
        let relativePath: String
    }

    private static let chromiumBrowsers: [ChromiumBrowser] = [
        ChromiumBrowser(displayName: "Chrome", relativePath: "Google/Chrome"),
        ChromiumBrowser(displayName: "Brave", relativePath: "BraveSoftware/Brave-Browser"),
        ChromiumBrowser(displayName: "Microsoft Edge", relativePath: "Microsoft Edge")
    ]

    static let safariBookmarksPath = "Library/Safari/Bookmarks.plist"
    /// Opens System Settings directly at the Full Disk Access pane. There is
    /// no API to request the permission itself — this only saves the person
    /// the navigation once they decide to grant it.
    static let fullDiskAccessSettingsURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")!

    /// - Parameter applicationSupportOverride: exists so a test can point
    ///   discovery at a synthetic directory instead of the real
    ///   `~/Library/Application Support`. Production call sites leave it
    ///   `nil`.
    static func detectSources(
        fileManager: FileManager = .default,
        applicationSupportOverride: URL? = nil
    ) -> [DetectedBookmarkSource] {
        let base = applicationSupportOverride
            ?? fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        var sources: [DetectedBookmarkSource] = []
        if let base {
            for browser in chromiumBrowsers {
                sources += detectProfiles(of: browser, under: base, fileManager: fileManager)
            }
        }
        sources.append(DetectedBookmarkSource(
            id: "safari",
            title: "Safari",
            kind: .safari,
            bookmarksFileURL: safariBookmarksURL(fileManager: fileManager),
            folderNamingLabel: "Safari"
        ))
        sources.append(DetectedBookmarkSource(
            id: "file",
            title: "Choose a file…",
            kind: .file,
            bookmarksFileURL: nil,
            folderNamingLabel: "a file"
        ))
        return sources
    }

    static func safariBookmarksURL(fileManager: FileManager = .default) -> URL {
        fileManager.homeDirectoryForCurrentUser.appendingPathComponent(safariBookmarksPath)
    }

    private static func detectProfiles(
        of browser: ChromiumBrowser,
        under applicationSupport: URL,
        fileManager: FileManager
    ) -> [DetectedBookmarkSource] {
        let root = applicationSupport.appendingPathComponent(browser.relativePath, isDirectory: true)
        guard let entries = try? fileManager.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) else {
            return []
        }
        let localStateData = try? Data(contentsOf: root.appendingPathComponent("Local State"))

        let profileDirectories = entries
            .map(\.lastPathComponent)
            .filter { $0 == "Default" || $0.hasPrefix("Profile ") }
            .sorted(by: profileDirectoryOrder)

        return profileDirectories.compactMap { directoryName in
            let bookmarksURL = root.appendingPathComponent(directoryName).appendingPathComponent("Bookmarks")
            guard fileManager.fileExists(atPath: bookmarksURL.path) else { return nil }
            let label = ChromiumProfileNaming.displayName(forProfileDirectory: directoryName, localState: localStateData)
            let title = label == directoryName ? "\(browser.displayName) — \(directoryName)" : "\(browser.displayName) — \(label)"
            return DetectedBookmarkSource(
                id: "\(browser.relativePath)/\(directoryName)",
                title: title,
                kind: .chromium,
                bookmarksFileURL: bookmarksURL,
                folderNamingLabel: browser.displayName
            )
        }
    }

    /// "Default" first, then "Profile 1", "Profile 2", … in numeric order —
    /// plain lexicographic sorting would put "Profile 10" before "Profile
    /// 2".
    private static func profileDirectoryOrder(_ lhs: String, _ rhs: String) -> Bool {
        if lhs == "Default" { return rhs != "Default" }
        if rhs == "Default" { return false }
        let leftNumber = Int(lhs.dropFirst("Profile ".count))
        let rightNumber = Int(rhs.dropFirst("Profile ".count))
        if let leftNumber, let rightNumber { return leftNumber < rightNumber }
        return lhs < rhs
    }
}

/// The destination folder's name: "Imported from Chrome — 21 August 2026".
/// One new top-level folder holds an entire import, preserving the source's
/// own structure beneath it — Clearframe never merges an import into a
/// folder that already exists.
enum BookmarkImportFolderNaming {
    static func destinationFolderTitle(sourceLabel: String, date: Date = Date()) -> String {
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
enum BookmarkSourceLoader {
    struct Loaded {
        let imported: BookmarkImport
        /// Entries the source held that could not be kept — an unsafe or
        /// missing address, most often — counted so the final report can be
        /// honest about them instead of letting them vanish silently.
        let unusableCount: Int
    }

    /// Not `Result<Loaded, Error>`: every failure here is already a plain,
    /// finished sentence for a person to read, never a raw parser exception
    /// a view would have to translate.
    enum Outcome {
        case success(Loaded)
        case failure(String)
    }

    static func load(from url: URL) -> Outcome {
        guard let data = try? Data(contentsOf: url) else {
            return .failure("Clearframe couldn't open that file.")
        }
        return load(data)
    }

    /// Exposed separately from `load(from:)` so a caller that already has
    /// the bytes — Safari's plist read, for instance — is not made to write
    /// them back out just to read them again.
    static func load(_ data: Data) -> Outcome {
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
                        "That file doesn't look like a bookmarks export Clearframe recognizes. In your "
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
            return .failure("Clearframe couldn't read that file as text.")
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
            return "Clearframe couldn't read that file."
        }
        switch importError {
        case .malformedJSON, .truncatedHTML:
            return "That file looks like it was cut off or damaged partway through. Try exporting it again."
        case .missingRoots, .notNetscapeDocument:
            return "That file doesn't look like a bookmarks export Clearframe recognizes."
        case .nestingTooDeep:
            return "That file's folders are nested far deeper than any real bookmarks file — Clearframe stopped reading it to stay safe."
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
