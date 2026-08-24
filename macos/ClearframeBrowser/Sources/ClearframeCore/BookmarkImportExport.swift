import Foundation

/// One imported bookmark, already validated the same way every other
/// bookmark entry point in Clearframe is: `WebURLPolicy` has approved the
/// address before this type can hold it.
public struct ImportedBookmark: Equatable, Sendable {
    public let title: String
    public let url: String
    public let addedAt: Date?

    public init(title: String, url: String, addedAt: Date?) {
        self.title = title
        self.url = url
        self.addedAt = addedAt
    }
}

/// One entry in an imported tree: either a leaf bookmark or a folder that
/// contains more of the same. `indirect` because a folder's children are
/// this same enum, recursively.
public indirect enum ImportedNode: Equatable, Sendable {
    case bookmark(ImportedBookmark)
    case folder(ImportedFolder)
}

/// What the source said one of its roots was.
///
/// Only meaningful on a root. A folder nested inside one is always
/// `.ordinary`, whatever it claims — every export format marks its bar
/// exactly once, at the top, and a marker deeper in the tree is a
/// hand-edited file rather than a second bar.
public enum ImportedFolderRole: String, Equatable, Sendable {
    /// The source's own bookmarks bar: Chromium's `roots.bookmark_bar` key,
    /// or Netscape HTML's `PERSONAL_TOOLBAR_FOLDER="true"` attribute.
    ///
    /// This is a structural fact, not a name. Chrome writes the folder's
    /// title as "toolbar" in some profiles, Firefox calls it "Bookmarks
    /// Toolbar", Safari calls it "Favorites", and a localized export calls
    /// it whatever that language calls it. Deciding which root is the bar
    /// by reading its title is therefore wrong in every one of those cases,
    /// which is the whole reason this exists.
    case bookmarksBar
    case ordinary
}

/// One imported folder and everything inside it, in the order the source
/// file listed them.
public struct ImportedFolder: Equatable, Sendable {
    public let title: String
    public let children: [ImportedNode]
    /// Defaulted so a folder is ordinary unless a parser positively says
    /// otherwise — the safe direction, since mistaking an ordinary folder
    /// for the bar would scatter it across somebody's bookmarks bar.
    public let role: ImportedFolderRole

    public init(title: String, children: [ImportedNode], role: ImportedFolderRole = .ordinary) {
        self.title = title
        self.children = children
        self.role = role
    }
}

/// The result of parsing an entire bookmarks file: one or more named roots
/// — "Bookmarks bar", "Other bookmarks", and so on — each holding a tree of
/// folders and bookmarks. Merging this into Clearframe's own
/// `BookmarkCollection` is a later step owned elsewhere; this type only
/// describes what the file contained.
public struct BookmarkImport: Equatable, Sendable {
    public let roots: [ImportedFolder]

    /// Normalizes the bar marker on the way in, so every later stage can
    /// trust it without re-checking: at most one root carries
    /// `.bookmarksBar`, and nothing below a root carries it at all.
    ///
    /// Enforced here rather than in each parser because it is a property of
    /// the format, not of one reader — a hand-edited HTML file can put
    /// `PERSONAL_TOOLBAR_FOLDER` on a folder six levels down, and a bar
    /// buried six levels down is not a bar.
    public init(roots: [ImportedFolder]) {
        var barClaimed = false
        self.roots = roots.map { root in
            let keepsRole = root.role == .bookmarksBar && !barClaimed
            if keepsRole { barClaimed = true }
            // Scan before rebuilding: a file with no nested marker at all —
            // which is every file any shipping browser writes — keeps its
            // parsed children untouched.
            let children = Self.containsBarMarker(root.children)
                ? Self.demotedToOrdinary(root.children)
                : root.children
            return ImportedFolder(
                title: root.title,
                children: children,
                role: keepsRole ? .bookmarksBar : .ordinary
            )
        }
    }

    /// Iterative, like `walk`: a corrupted tree should not be able to
    /// overflow a stack merely by being asked whether it is corrupted.
    private static func containsBarMarker(_ nodes: [ImportedNode]) -> Bool {
        var stack = nodes
        while let node = stack.popLast() {
            guard case .folder(let folder) = node else { continue }
            if folder.role == .bookmarksBar { return true }
            stack.append(contentsOf: folder.children)
        }
        return false
    }

    /// Recursive, and safe to be for the same reason the merge planner's
    /// prune is: this tree already passed a parser's own depth cap
    /// (`BookmarkImportLimits.maxNestingDepth`) before it could reach here.
    /// Only ever entered once `containsBarMarker` has said there is
    /// something to fix.
    private static func demotedToOrdinary(_ nodes: [ImportedNode]) -> [ImportedNode] {
        nodes.map { node in
            guard case .folder(let folder) = node else { return node }
            return .folder(ImportedFolder(
                title: folder.title,
                children: demotedToOrdinary(folder.children),
                role: .ordinary
            ))
        }
    }

    /// The root the source itself called its bar, if it said so at all.
    ///
    /// At most one: a file marking several is read as marking the first,
    /// because every format defines the marker as singular and a second one
    /// carries no information about which was meant.
    public var bookmarksBarRoot: ImportedFolder? {
        roots.first { $0.role == .bookmarksBar }
    }

    /// Whether the source identified a bar at all. A file that did not —
    /// an older export, or a format with no such concept — is not broken;
    /// it just cannot be merged onto a bar by anything but a guess, and
    /// Clearframe does not guess.
    public var declaresBookmarksBar: Bool { bookmarksBarRoot != nil }

    /// Every bookmark anywhere in the tree, however deep.
    public var bookmarkCount: Int {
        Self.walk(roots).bookmarks
    }

    /// Every folder anywhere in the tree, not counting the roots themselves.
    ///
    /// Mirrors `BookmarkDescendantCounts`, where a folder never counts
    /// itself: the roots are permanent containers a browser writes on every
    /// export, not folders a person made, so they are not counted as one of
    /// "their" folders either.
    public var folderCount: Int {
        Self.walk(roots).folders
    }

    /// Iterative on purpose, the same way `BookmarkCollection.descendantCounts()`
    /// is: a hand-crafted or corrupted import already passed the parser's own
    /// depth cap, but counting should never be the thing that overflows a
    /// stack on top of it.
    private static func walk(_ roots: [ImportedFolder]) -> (bookmarks: Int, folders: Int) {
        var bookmarkTotal = 0
        var folderTotal = 0
        var stack: [ImportedNode] = roots.flatMap(\.children)
        while let node = stack.popLast() {
            switch node {
            case .bookmark:
                bookmarkTotal += 1
            case .folder(let folder):
                folderTotal += 1
                stack.append(contentsOf: folder.children)
            }
        }
        return (bookmarkTotal, folderTotal)
    }
}

/// Everything that can go wrong reading a file Clearframe did not write,
/// explained the way a person reading an import error would need it
/// explained — never a raw parser exception.
public enum BookmarkImportError: Error, Equatable, Sendable {
    /// The bytes are not valid JSON, or stopped partway through — a file
    /// that was truncated, corrupted, or was never a Chrome `Bookmarks`
    /// file to begin with.
    case malformedJSON
    /// Valid JSON, but there is no `roots` object, or it named no folders
    /// Clearframe recognizes — not a Chromium bookmarks file.
    case missingRoots
    /// No `<DL` appears anywhere in the text — not Netscape bookmark HTML,
    /// unclosed tags or not.
    case notNetscapeDocument
    /// A tag, or a quoted attribute value inside one, never closed before
    /// the text ended. Real Netscape exports always finish their tags even
    /// though they skip `</DT>`; a break this specific means the file was
    /// cut off mid-write or mid-download.
    case truncatedHTML
    /// Folder nesting passed the depth cap (256 levels). No browser writes
    /// bookmarks this deep; a file shaped like this is either corrupted or
    /// hand-crafted to overrun a naive parser.
    case nestingTooDeep
}

/// Shared between both importers so the cap can only ever be tuned in one
/// place.
enum BookmarkImportLimits {
    static let maxNestingDepth = 256
}

/// HTML entity handling for Netscape bookmark titles: `NetscapeBookmarkImporter`
/// unescapes what it reads, `NetscapeBookmarkExporter` escapes what it
/// writes, and both need to agree on exactly the same five characters or a
/// round trip would drift.
enum NetscapeHTMLEntities {
    /// The five entities `bookmark_html_writer.cc` actually emits, plus
    /// numeric entities (`&#39;`, `&#x2019;`, …) accepted on the way in
    /// since other browsers' exporters are free to use them.
    static func unescape(_ value: String) -> String {
        guard value.contains("&") else { return value }
        var result = ""
        result.reserveCapacity(value.count)
        var remainder = Substring(value)
        while let ampersandIndex = remainder.firstIndex(of: "&") {
            result += remainder[remainder.startIndex..<ampersandIndex]
            let afterAmpersand = remainder[remainder.index(after: ampersandIndex)...]
            // A real entity is short; a bare '&' followed by a long run of
            // text with no ';' is just an unescaped ampersand in the wild,
            // which malformed real-world files do contain.
            if let semicolonIndex = afterAmpersand.firstIndex(of: ";"),
               afterAmpersand.distance(from: afterAmpersand.startIndex, to: semicolonIndex) <= 12,
               let decoded = decodeEntityName(String(afterAmpersand[afterAmpersand.startIndex..<semicolonIndex])) {
                result.append(decoded)
                remainder = afterAmpersand[afterAmpersand.index(after: semicolonIndex)...]
            } else {
                result.append("&")
                remainder = afterAmpersand
            }
        }
        result += remainder
        return result
    }

    private static func decodeEntityName(_ name: String) -> Character? {
        switch name {
        case "amp": return "&"
        case "lt": return "<"
        case "gt": return ">"
        case "quot": return "\""
        case "apos", "#39": return "'"
        default:
            if name.hasPrefix("#x") || name.hasPrefix("#X"),
               let code = UInt32(name.dropFirst(2), radix: 16),
               let scalar = Unicode.Scalar(code) {
                return Character(scalar)
            }
            if name.hasPrefix("#"),
               let code = UInt32(name.dropFirst()),
               let scalar = Unicode.Scalar(code) {
                return Character(scalar)
            }
            return nil
        }
    }

    /// The same five characters, single-pass so nothing is ever escaped
    /// twice.
    static func escape(_ value: String) -> String {
        var result = ""
        result.reserveCapacity(value.count)
        for character in value {
            switch character {
            case "&": result += "&amp;"
            case "<": result += "&lt;"
            case ">": result += "&gt;"
            case "\"": result += "&quot;"
            case "'": result += "&#39;"
            default: result.append(character)
            }
        }
        return result
    }
}

/// The same "empty title falls back to the address" rule
/// `BrowserDataStore` already applies when it files a page — an imported
/// entry with no title is not an error, it is just unnamed.
func fallbackBookmarkTitle(rawTitle: String, validatedURL: URL) -> String {
    let trimmed = rawTitle.trimmingCharacters(in: .whitespacesAndNewlines)
    if !trimmed.isEmpty { return trimmed }
    return validatedURL.host ?? validatedURL.absoluteString
}
