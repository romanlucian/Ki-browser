import Foundation

/// Reads the `Bookmarks` file every Chromium-family browser writes —
/// Chrome, Brave, Edge — verified against `bookmark_codec.cc` rather than
/// guessed from a sample export. See `docs/browser-feature-research.md`
/// section 3 for the schema and the timestamp math this implements.
public enum ChromiumBookmarkImporter {
    /// Chrome's own interface names for the roots the file calls
    /// `bookmark_bar`, `other`, and `synced`. Order here is the order Chrome
    /// shows them in, and the order `roots` comes back in.
    private static let knownRoots: [(key: String, displayName: String)] = [
        ("bookmark_bar", "Bookmarks bar"),
        ("other", "Other bookmarks"),
        ("synced", "Mobile bookmarks")
    ]

    /// Microseconds between the Windows/Chromium epoch (1601-01-01 UTC) and
    /// the Unix epoch. Verified against `base/time/time.h`.
    private static let microsecondsFromWindowsToUnixEpoch: Int64 = 11_644_473_600_000_000

    public static func parse(_ data: Data) throws -> BookmarkImport {
        let jsonObject: Any
        do {
            jsonObject = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
        } catch {
            throw BookmarkImportError.malformedJSON
        }

        guard let root = jsonObject as? [String: Any],
              let rootsObject = root["roots"] as? [String: Any] else {
            throw BookmarkImportError.missingRoots
        }

        var roots: [ImportedFolder] = []
        var seenKeys: Set<String> = []

        for (key, displayName) in knownRoots {
            seenKeys.insert(key)
            guard let node = rootsObject[key] as? [String: Any] else { continue }
            roots.append(try parseFolder(node, titleOverride: displayName, depth: 1))
        }

        // Chrome has written exactly these three roots for years, but a
        // future root or a hand-edited file should still surface its
        // contents rather than silently vanish. Sorted so output order
        // never depends on JSON key enumeration order.
        let extraKeys = rootsObject.keys.filter { !seenKeys.contains($0) }.sorted()
        for key in extraKeys {
            guard let node = rootsObject[key] as? [String: Any] else { continue }
            roots.append(try parseFolder(node, titleOverride: nil, depth: 1))
        }

        guard !roots.isEmpty else { throw BookmarkImportError.missingRoots }
        return BookmarkImport(roots: roots)
    }

    private static func parseFolder(
        _ node: [String: Any],
        titleOverride: String?,
        depth: Int
    ) throws -> ImportedFolder {
        // In practice, Foundation's own `JSONSerialization` reader refuses
        // input this deep on its own (empirically, somewhere around 256
        // levels in this schema, where every folder level costs one
        // dictionary plus one array) and surfaces as `.malformedJSON` from
        // `parse(_:)` before this guard ever runs. It stays here anyway as
        // the same defense-in-depth `NetscapeBookmarkImporter` relies on,
        // since nothing guarantees every Foundation version enforces that
        // limit, or enforces it at the same depth.
        guard depth <= BookmarkImportLimits.maxNestingDepth else {
            throw BookmarkImportError.nestingTooDeep
        }

        let rawName = (node["name"] as? String) ?? ""
        let title = titleOverride ?? (rawName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "Bookmarks"
            : rawName)

        var children: [ImportedNode] = []
        for entry in (node["children"] as? [Any]) ?? [] {
            guard let childNode = entry as? [String: Any], let type = childNode["type"] as? String else {
                continue // Not a shape this format defines; skip rather than fail the whole import.
            }
            switch type {
            case "folder":
                children.append(.folder(try parseFolder(childNode, titleOverride: nil, depth: depth + 1)))
            case "url":
                if let bookmark = parseBookmark(childNode) {
                    children.append(.bookmark(bookmark))
                }
            default:
                continue // e.g. a future node type Clearframe does not know about yet.
            }
        }
        return ImportedFolder(title: title, children: children)
    }

    /// `nil` means "skip this entry" — an invalid or non-web URL is not a
    /// reason to fail the whole file.
    private static func parseBookmark(_ node: [String: Any]) -> ImportedBookmark? {
        guard let urlString = node["url"] as? String,
              let validURL = WebURLPolicy.validatedURL(urlString) else { return nil }
        let rawName = (node["name"] as? String) ?? ""
        let title = fallbackBookmarkTitle(rawTitle: rawName, validatedURL: validURL)
        return ImportedBookmark(title: title, url: validURL.absoluteString, addedAt: date(from: node["date_added"]))
    }

    /// Chrome serializes int64 timestamps as JSON strings to avoid losing
    /// precision, but a hand-built fixture may reasonably use a JSON number
    /// instead — both are accepted. `0` means "never set" and comes back as
    /// `nil`, not the year 1601.
    private static func date(from rawValue: Any?) -> Date? {
        let microseconds: Int64?
        if let stringValue = rawValue as? String {
            microseconds = Int64(stringValue)
        } else if let numberValue = rawValue as? NSNumber {
            microseconds = numberValue.int64Value
        } else {
            microseconds = nil
        }
        guard let microseconds, microseconds != 0 else { return nil }
        let unixMicroseconds = microseconds - microsecondsFromWindowsToUnixEpoch
        return Date(timeIntervalSince1970: Double(unixMicroseconds) / 1_000_000)
    }
}
