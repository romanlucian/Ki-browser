import Foundation

/// Where a bookmark found outside any named folder — legal but unusual —
/// is filed, since `BookmarkImport.roots` only holds folders.
private let strayTopLevelBookmarksFolderTitle = "Bookmarks"
/// What an `<H3>` with no text, or no `<H3>` at all, becomes. Never silent:
/// an empty string here would just be a folder nobody can see in a list.
private let untitledFolderFallbackTitle = "Untitled folder"

/// Reads the Netscape bookmark HTML format — verified verbatim against
/// Chromium's `bookmark_html_writer.cc` — which is what every mainstream
/// browser both writes and reads, making it the universal bookmark
/// interchange format. See `docs/browser-feature-research.md` section 3.
///
/// This is unclosed-tag SGML, not valid HTML or XML: real files never carry
/// a `</DT>`, so a DOM parser refuses them outright. What follows is a
/// permissive, hand-rolled tag scanner instead — it tolerates every missing
/// closing tag a real export omits, and only refuses input where a tag or a
/// quoted attribute value is cut off before it ever closes, which is what an
/// interrupted download or a half-written file looks like.
public enum NetscapeBookmarkImporter {
    public static func parse(_ html: String) throws -> BookmarkImport {
        guard html.range(of: "<dl", options: [.caseInsensitive]) != nil else {
            throw BookmarkImportError.notNetscapeDocument
        }

        var walker = Walker(characters: Array(html))
        try walker.run()

        guard !walker.roots.isEmpty else { throw BookmarkImportError.notNetscapeDocument }
        return BookmarkImport(roots: walker.roots)
    }

    /// One `<DL>` currently open while scanning: the folder title it was
    /// introduced with (from the `<H3>` immediately before it, if any) and
    /// whatever children have been appended to it so far.
    private struct OpenList {
        var title: String
        var children: [ImportedNode] = []
    }

    /// All scanning state in one place so `parse` stays a thin entry point.
    /// A `struct` rather than free functions because the tag-by-tag walk
    /// needs to thread a lot of small pieces of state (the stack, the
    /// pending folder title, depth) through every branch.
    private struct Walker {
        let characters: [Character]
        var index = 0
        var stack: [OpenList] = []
        var roots: [ImportedFolder] = []
        var pendingFolderTitle: String?

        init(characters: [Character]) {
            self.characters = characters
        }

        mutating func run() throws {
            while index < characters.count {
                if characters[index] == "<" {
                    try consumeTag()
                } else {
                    index += 1
                }
            }
            // EOF with folders still open is the expected shape for a real
            // file (no closing `</DL>` guarantee at the very end is not
            // assumed either) — close them exactly as an explicit `</DL>`
            // would, innermost first.
            while !stack.isEmpty {
                closeCurrentList()
            }
        }

        private mutating func consumeTag() throws {
            guard let tag = readTag() else { throw BookmarkImportError.truncatedHTML }

            switch (tag.isClosing, tag.name) {
            case (false, "DL"):
                guard stack.count < BookmarkImportLimits.maxNestingDepth else {
                    throw BookmarkImportError.nestingTooDeep
                }
                stack.append(OpenList(title: pendingFolderTitle ?? ""))
                pendingFolderTitle = nil

            case (true, "DL"):
                closeCurrentList()

            case (false, "H3"):
                pendingFolderTitle = NetscapeHTMLEntities.unescape(readText())

            case (false, "A"):
                let rawTitle = NetscapeHTMLEntities.unescape(readText())
                if let bookmark = makeBookmark(attributes: tag.attributes, rawTitle: rawTitle) {
                    append(.bookmark(bookmark))
                }

            default:
                break // <DT>, </DT>, <p>, </A>, </H3>, <!DOCTYPE …>, <META …>, <TITLE>/</TITLE>, <H1>/</H1>, …
            }
        }

        /// Reads everything between `<` and the matching `>`, respecting
        /// quoted attribute values so a stray `>` inside one (unusual, but
        /// not impossible in a malformed file) does not end the tag early.
        /// `nil` means the text ended before the tag did.
        private mutating func readTag() -> (isClosing: Bool, name: String, attributes: [String: String])? {
            precondition(characters[index] == "<")
            var cursor = index + 1
            var quote: Character?
            var body: [Character] = []
            while cursor < characters.count {
                let character = characters[cursor]
                if let openQuote = quote {
                    body.append(character)
                    if character == openQuote { quote = nil }
                    cursor += 1
                    continue
                }
                if character == "\"" || character == "'" {
                    quote = character
                    body.append(character)
                    cursor += 1
                    continue
                }
                if character == ">" {
                    index = cursor + 1
                    return parseTagBody(body)
                }
                body.append(character)
                cursor += 1
            }
            return nil // Ran off the end still inside the tag (or its quoted value): truncated.
        }

        /// Everything from the current position up to (not including) the
        /// next `<`. Title text always sits right after an opening `<A>` or
        /// `<H3>`, whether or not the file bothers to close them, so this is
        /// the entire "read the title" story.
        private mutating func readText() -> String {
            var text = ""
            while index < characters.count, characters[index] != "<" {
                text.append(characters[index])
                index += 1
            }
            return text
        }

        private func parseTagBody(_ body: [Character]) -> (isClosing: Bool, name: String, attributes: [String: String]) {
            var cursor = 0
            func skipWhitespace() { while cursor < body.count, body[cursor].isWhitespace { cursor += 1 } }

            skipWhitespace()
            let isClosing = cursor < body.count && body[cursor] == "/"
            if isClosing { cursor += 1 }

            var name = ""
            while cursor < body.count, !body[cursor].isWhitespace, body[cursor] != "/" {
                name.append(body[cursor])
                cursor += 1
            }

            var attributes: [String: String] = [:]
            while cursor < body.count {
                skipWhitespace()
                guard cursor < body.count, body[cursor] != "/" else { break }

                var key = ""
                while cursor < body.count, body[cursor] != "=", !body[cursor].isWhitespace, body[cursor] != "/" {
                    key.append(body[cursor])
                    cursor += 1
                }
                skipWhitespace()

                guard !key.isEmpty else { break }
                guard cursor < body.count, body[cursor] == "=" else {
                    attributes[key.lowercased()] = ""
                    continue
                }
                cursor += 1
                skipWhitespace()

                if cursor < body.count, body[cursor] == "\"" || body[cursor] == "'" {
                    let quote = body[cursor]
                    cursor += 1
                    var value = ""
                    while cursor < body.count, body[cursor] != quote {
                        value.append(body[cursor])
                        cursor += 1
                    }
                    if cursor < body.count { cursor += 1 } // closing quote
                    attributes[key.lowercased()] = value
                } else {
                    var value = ""
                    while cursor < body.count, !body[cursor].isWhitespace {
                        value.append(body[cursor])
                        cursor += 1
                    }
                    attributes[key.lowercased()] = value
                }
            }

            return (isClosing, name.uppercased(), attributes)
        }

        /// `nil` when the HREF is missing, unparseable, or not `http`/`https`
        /// — never fatal, the entry is simply left out of the import. The
        /// `ICON` attribute (a base64 data URI) is present in `tag.attributes`
        /// like everything else, and is never read.
        private func makeBookmark(attributes: [String: String], rawTitle: String) -> ImportedBookmark? {
            guard let href = attributes["href"], let validURL = WebURLPolicy.validatedURL(href) else { return nil }
            let title = fallbackBookmarkTitle(rawTitle: rawTitle, validatedURL: validURL)
            let addedAt = attributes["add_date"].flatMap(TimeInterval.init).flatMap { seconds -> Date? in
                seconds != 0 ? Date(timeIntervalSince1970: seconds) : nil
            }
            return ImportedBookmark(title: title, url: validURL.absoluteString, addedAt: addedAt)
        }

        /// Appends into whatever is currently open. With nothing open — a
        /// bookmark or folder sitting outside any `<DL>`, or the spill-out
        /// from closing the outermost one — a folder becomes a root
        /// directly, and a bookmark is filed into a shared synthetic root,
        /// since `BookmarkImport.roots` only holds folders.
        private mutating func append(_ node: ImportedNode) {
            guard stack.isEmpty else {
                stack[stack.count - 1].children.append(node)
                return
            }
            switch node {
            case .folder(let folder):
                roots.append(folder)
            case .bookmark(let bookmark):
                if let existingIndex = roots.firstIndex(where: { $0.title == strayTopLevelBookmarksFolderTitle }) {
                    roots[existingIndex] = ImportedFolder(
                        title: strayTopLevelBookmarksFolderTitle,
                        children: roots[existingIndex].children + [.bookmark(bookmark)]
                    )
                } else {
                    roots.append(ImportedFolder(title: strayTopLevelBookmarksFolderTitle, children: [.bookmark(bookmark)]))
                }
            }
        }

        /// Closes the innermost open `<DL>`. The outermost one in a real file
        /// is the document's root list, not a folder itself, so closing it
        /// spills its children back through `append` instead of wrapping
        /// them all in one more nameless folder.
        private mutating func closeCurrentList() {
            guard let finished = stack.popLast() else { return } // stray </DL>, nothing open: ignore.

            if stack.isEmpty {
                for child in finished.children { append(child) }
            } else {
                let title = finished.title.trimmingCharacters(in: .whitespacesAndNewlines)
                let folder = ImportedFolder(
                    title: title.isEmpty ? untitledFolderFallbackTitle : title,
                    children: finished.children
                )
                stack[stack.count - 1].children.append(.folder(folder))
            }
        }
    }
}
