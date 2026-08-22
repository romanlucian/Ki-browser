import AppKit
import ClearframeCore
import UniformTypeIdentifiers

/// The Bookmarks menu's "Export Bookmarks…" command: writes every saved
/// bookmark and folder out as the same Netscape HTML format every mainstream
/// browser can read back in, so leaving Clearframe is as easy as arriving.
/// Puts a standard macOS save panel in front of the person before anything is
/// written; nothing here runs on its own.
@MainActor
enum BookmarkExportCommand {
    static func run(store: BrowserDataStore) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.html]
        panel.nameFieldStringValue = "Clearframe Bookmarks.html"
        panel.message = "Save your bookmarks as a file every browser can import."
        panel.prompt = "Export"
        guard panel.runModal() == .OK, let destination = panel.url else { return }

        let html = NetscapeBookmarkExporter.html(folders: store.bookmarkFolders, bookmarks: store.bookmarks)
        do {
            try html.write(to: destination, atomically: true, encoding: .utf8)
        } catch {
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = "Couldn't save your bookmarks"
            alert.informativeText = "Clearframe couldn't write that file. Check that the location is still available, then try again."
            alert.addButton(withTitle: "OK")
            alert.runModal()
        }
    }
}
