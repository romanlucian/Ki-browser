import Foundation

/// Writes the same Netscape bookmark HTML format `NetscapeBookmarkImporter`
/// reads — the format every mainstream browser can import — so leaving
/// Clearframe is as easy as arriving. Shape verified verbatim against
/// Chromium's own `bookmark_html_writer.cc`.
public enum NetscapeBookmarkExporter {
    /// Clearframe has no "Other bookmarks" bucket of its own — everything
    /// with no parent folder already sits on the bar (`BookmarkBarViews`
    /// reads exactly that: `folders(in: nil)` and `bookmarks(in: nil)`). So
    /// there is exactly one root to write, and it carries
    /// `PERSONAL_TOOLBAR_FOLDER="true"` because it is, honestly, the bar.
    private static let barFolderTitle = "Bookmarks bar"

    public static func html(folders: [BookmarkFolderRecord], bookmarks: [BookmarkRecord]) -> String {
        // Reuses `BookmarkCollection`'s own ordering and cycle-breaking
        // rather than re-deriving them: the export order for a level is
        // exactly what the bar and folder views already show — folders
        // first in position order, then bookmarks in position order.
        let collection = BookmarkCollection(folders: folders, bookmarks: bookmarks)
        let barAddDate = Int(Date().timeIntervalSince1970)

        var output = ""
        output += "<!DOCTYPE NETSCAPE-Bookmark-file-1>\n"
        output += "<META HTTP-EQUIV=\"Content-Type\" CONTENT=\"text/html; charset=UTF-8\">\n"
        output += "<TITLE>Bookmarks</TITLE>\n"
        output += "<H1>Bookmarks</H1>\n"
        output += "<DL><p>\n"
        output += "    <DT><H3 ADD_DATE=\"\(barAddDate)\" LAST_MODIFIED=\"\(barAddDate)\" PERSONAL_TOOLBAR_FOLDER=\"true\">"
        output += "\(NetscapeHTMLEntities.escape(barFolderTitle))</H3>\n"
        output += "    <DL><p>\n"
        output += renderChildren(of: nil, collection: collection, indent: "        ")
        output += "    </DL><p>\n"
        output += "</DL><p>\n"
        return output
    }

    private static func renderChildren(of parentID: UUID?, collection: BookmarkCollection, indent: String) -> String {
        var output = ""
        for folder in collection.folders(in: parentID) {
            output += renderFolder(folder, collection: collection, indent: indent)
        }
        for bookmark in collection.bookmarks(in: parentID) {
            output += renderBookmark(bookmark, indent: indent)
        }
        return output
    }

    private static func renderFolder(_ folder: BookmarkFolderRecord, collection: BookmarkCollection, indent: String) -> String {
        let addDate = Int(folder.createdAt.timeIntervalSince1970)
        var output = "\(indent)<DT><H3 ADD_DATE=\"\(addDate)\" LAST_MODIFIED=\"\(addDate)\">"
        output += "\(NetscapeHTMLEntities.escape(folder.title))</H3>\n"
        output += "\(indent)<DL><p>\n"
        output += renderChildren(of: folder.id, collection: collection, indent: indent + "    ")
        output += "\(indent)</DL><p>\n"
        return output
    }

    private static func renderBookmark(_ bookmark: BookmarkRecord, indent: String) -> String {
        let addDate = Int(bookmark.createdAt.timeIntervalSince1970)
        let href = NetscapeHTMLEntities.escape(bookmark.url)
        let title = NetscapeHTMLEntities.escape(bookmark.title)
        return "\(indent)<DT><A HREF=\"\(href)\" ADD_DATE=\"\(addDate)\">\(title)</A>\n"
    }
}
