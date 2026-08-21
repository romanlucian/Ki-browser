import AppKit
import UniformTypeIdentifiers

/// The File menu's page commands: opening a file from the disk, saving the
/// page on screen, and handing its address to another app.
///
/// All three are started by the person, from a menu, and each one puts a
/// standard macOS panel in front of them before anything happens. Nothing here
/// runs on its own, and no page can reach any of it.
@MainActor
enum PageFileCommands {
    /// What an open panel offers. A browser engine renders web documents,
    /// images, and PDFs; offering everything else would invite files WebKit
    /// answers with a download prompt or a blank page.
    static var openableTypes: [UTType] {
        [.html, .xml, .pdf, .plainText, .image, .svg, .webArchive]
            .compactMap { $0 }
    }

    /// Asks for a file and hands it back. Returns nil if the person cancels.
    static func chooseFileToOpen() -> URL? {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = openableTypes
        panel.message = "Choose a page or document to open in Clearframe."
        panel.prompt = "Open"
        guard panel.runModal() == .OK else { return nil }
        return panel.url
    }

    /// Saves what the web view currently holds. WebKit writes a web archive:
    /// one file carrying the page and the resources it is showing, so the
    /// saved copy matches what was on screen rather than whatever the address
    /// would return if it were fetched again.
    static func savePage(
        named suggestedName: String,
        archivedBy archive: @escaping (@escaping (Result<Data, Error>) -> Void) -> Void,
        completion: @escaping (Result<URL, Error>) -> Void
    ) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.webArchive].compactMap { $0 }
        panel.nameFieldStringValue = safeFileName(from: suggestedName)
        panel.message = "Save this page, with the images and styles it is showing."
        panel.prompt = "Save"
        guard panel.runModal() == .OK, let destination = panel.url else { return }
        archive { result in
            switch result {
            case .success(let data):
                do {
                    try data.write(to: destination, options: .atomic)
                    completion(.success(destination))
                } catch {
                    completion(.failure(error))
                }
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }

    /// Writes the page out as a PDF, after the person names it.
    static func exportPDF(
        named suggestedName: String,
        renderedBy render: @escaping (@escaping (Result<Data, Error>) -> Void) -> Void,
        completion: @escaping (Result<URL, Error>) -> Void
    ) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        panel.nameFieldStringValue = safeFileName(from: suggestedName)
        panel.message = "Export this page as a PDF."
        panel.prompt = "Export"
        guard panel.runModal() == .OK, let destination = panel.url else { return }
        render { result in
            switch result {
            case .success(let data):
                do {
                    try data.write(to: destination, options: .atomic)
                    completion(.success(destination))
                } catch {
                    completion(.failure(error))
                }
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }

    /// Offers the page's address to the apps the person has, through the
    /// system's own picker. Only the address travels — never the page's text,
    /// and never without a destination being chosen in that picker.
    static func share(_ url: URL, from view: NSView?) {
        let picker = NSSharingServicePicker(items: [url])
        guard let anchor = view ?? NSApp.keyWindow?.contentView else { return }
        picker.show(
            relativeTo: CGRect(x: anchor.bounds.midX, y: anchor.bounds.maxY - 60, width: 1, height: 1),
            of: anchor,
            preferredEdge: .minY
        )
    }

    /// A page title is not a filename: it can run to a paragraph and contain
    /// slashes and colons, which would either fail to write or land somewhere
    /// unexpected.
    static func safeFileName(from title: String) -> String {
        let collapsed = title
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        let cleaned = collapsed.components(separatedBy: CharacterSet(charactersIn: "/\\:*?\"<>|")).joined(separator: "-")
        let trimmed = String(cleaned.prefix(80)).trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? "Untitled Page" : trimmed
    }
}
