import AppKit
import Combine
import Foundation
@preconcurrency import WebKit

enum DownloadStatus: Equatable {
    case choosingDestination
    case downloading
    case finished
    case cancelled
    case failed(String)

    var label: String {
        switch self {
        case .choosingDestination: return "Choose where to save"
        case .downloading: return "Downloading…"
        case .finished: return "Downloaded"
        case .cancelled: return "Cancelled"
        case .failed(let message): return "Failed: \(message)"
        }
    }

    var isActive: Bool {
        self == .choosingDestination || self == .downloading
    }
}

struct DownloadItem: Identifiable, Equatable {
    let id: UUID
    var filename: String
    let sourceURL: URL?
    var destinationURL: URL?
    var status: DownloadStatus
    let startedAt: Date
}

@MainActor
final class DownloadCenter: NSObject, ObservableObject {
    static let emptyStateTitle = "No downloads yet"
    static let emptyStateMessage = "Downloads from this session appear here after you choose where to save them."

    @Published private(set) var items: [DownloadItem] = []
    @Published var isShelfVisible = false
    @Published var isPanelPresented = false

    private var itemIDByDownload: [ObjectIdentifier: UUID] = [:]
    private var downloadsByItemID: [UUID: WKDownload] = [:]

    var activeCount: Int {
        items.filter { $0.status.isActive }.count
    }

    var downloadsDirectory: URL? {
        FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
    }

    func togglePanel() {
        isPanelPresented.toggle()
    }

    /// Opens where files are actually being saved, which is the folder chosen
    /// in Settings when Limeghost is not asking, and the Mac's own Downloads
    /// otherwise. Opening `~/Downloads` while writing somewhere else sends
    /// somebody to an empty folder to look for a file that is not there.
    func openDownloadsFolder() {
        guard let folder = BrowserPreferences.shared.resolvedDownloadFolder ?? downloadsDirectory else { return }
        NSWorkspace.shared.open(folder)
    }

    func track(_ download: WKDownload, sourceURL: URL?) {
        let key = ObjectIdentifier(download)
        guard itemIDByDownload[key] == nil else { return }
        let id = UUID()
        itemIDByDownload[key] = id
        downloadsByItemID[id] = download
        items.insert(
            DownloadItem(
                id: id,
                filename: sourceURL?.lastPathComponent.nilIfEmpty ?? "Download",
                sourceURL: sourceURL,
                destinationURL: nil,
                status: .choosingDestination,
                startedAt: Date()
            ),
            at: 0
        )
        isShelfVisible = true
        download.delegate = self
    }

    func cancel(_ item: DownloadItem) {
        guard let download = downloadsByItemID[item.id] else { return }
        update(item.id) { $0.status = .cancelled }
        download.cancel { [weak self] _ in
            Task { @MainActor in self?.removeTracking(download, id: item.id) }
        }
    }

    func reveal(_ item: DownloadItem) {
        guard let destination = item.destinationURL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([destination])
    }

    func clearFinished() {
        let removable = Set(items.filter { !$0.status.isActive }.map(\.id))
        items.removeAll { removable.contains($0.id) }
        for id in removable { downloadsByItemID.removeValue(forKey: id) }
        if items.isEmpty { isShelfVisible = false }
    }

    /// Clears in-app download metadata without deleting files the user chose to save.
    /// The Settings reset is disabled while a transfer or save panel is active.
    func clearAllRecords() {
        guard activeCount == 0 else { return }
        items.removeAll()
        itemIDByDownload.removeAll()
        downloadsByItemID.removeAll()
        isShelfVisible = false
        isPanelPresented = false
    }

    private func update(_ id: UUID, change: (inout DownloadItem) -> Void) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        change(&items[index])
    }

    private func id(for download: WKDownload) -> UUID? {
        itemIDByDownload[ObjectIdentifier(download)]
    }

    private func removeTracking(_ download: WKDownload, id: UUID) {
        itemIDByDownload.removeValue(forKey: ObjectIdentifier(download))
        downloadsByItemID.removeValue(forKey: id)
    }
}

extension DownloadCenter {
    /// A name inside `folder` that no file already uses.
    ///
    /// The save-panel path may replace a file because the person was shown the
    /// name and chose Replace. Saving without asking has no such consent, so a
    /// second download of one file becomes `report 2.pdf` rather than silently
    /// destroying the first.
    static func availableURL(in folder: URL, named filename: String) -> URL {
        let candidate = folder.appendingPathComponent(filename)
        guard FileManager.default.fileExists(atPath: candidate.path) else { return candidate }
        let base = candidate.deletingPathExtension().lastPathComponent
        let ext = candidate.pathExtension
        for suffix in 2...999 {
            let name = ext.isEmpty ? "\(base) \(suffix)" : "\(base) \(suffix).\(ext)"
            let next = folder.appendingPathComponent(name)
            if !FileManager.default.fileExists(atPath: next.path) { return next }
        }
        // Nine hundred and ninety-nine of one name is absurd, but returning the
        // occupied original would hand WKDownload a destination it fails on.
        // A stamped name is ugly and free.
        let stamp = UUID().uuidString.prefix(8)
        let name = ext.isEmpty ? "\(base) \(stamp)" : "\(base) \(stamp).\(ext)"
        return folder.appendingPathComponent(name)
    }
}

extension DownloadCenter: WKDownloadDelegate {
    func download(
        _ download: WKDownload,
        decideDestinationUsing response: URLResponse,
        suggestedFilename: String,
        completionHandler: @escaping (URL?) -> Void
    ) {
        guard let id = id(for: download) else {
            completionHandler(nil)
            return
        }

        let safeFilename = URL(fileURLWithPath: suggestedFilename).lastPathComponent.nilIfEmpty ?? "Download"

        // Settings → Downloads can send files straight to a folder. It answers
        // nil when the person still wants to be asked, and also when the folder
        // has gone or cannot be written to — the app is not sandboxed, so a
        // folder can be pickable and then refused by the privacy system.
        // Falling back to the panel is visible; a download that says only
        // "failed" is not.
        if let folder = BrowserPreferences.shared.resolvedDownloadFolder {
            let destination = Self.availableURL(in: folder, named: safeFilename)
            // The same bookkeeping the panel path does below. Without it the
            // shelf sits on "Choose where to save" for the whole transfer and
            // Reveal does nothing afterwards, because the item never learns
            // where the file went.
            update(id) {
                $0.filename = destination.lastPathComponent
                $0.destinationURL = destination
                $0.status = .downloading
            }
            completionHandler(destination)
            return
        }

        let panel = NSSavePanel()
        panel.title = "Save Download"
        panel.prompt = "Download"
        panel.nameFieldStringValue = safeFilename
        panel.canCreateDirectories = true
        panel.directoryURL = downloadsDirectory

        panel.begin { [weak self] result in
            Task { @MainActor in
                guard let self else {
                    completionHandler(nil)
                    return
                }
                guard result == .OK, let destination = panel.url else {
                    self.update(id) { $0.status = .cancelled }
                    self.removeTracking(download, id: id)
                    completionHandler(nil)
                    return
                }
                guard self.items.first(where: { $0.id == id })?.status != .cancelled else {
                    self.removeTracking(download, id: id)
                    completionHandler(nil)
                    return
                }
                // The save panel already offered Replace and the user chose it,
                // but WKDownload refuses to write over a file that exists and
                // ends the transfer as Failed. The file the user agreed to
                // replace is removed here, after that consent and nowhere else.
                if FileManager.default.fileExists(atPath: destination.path) {
                    do {
                        try FileManager.default.removeItem(at: destination)
                    } catch {
                        self.update(id) {
                            $0.status = .failed("Limeghost could not replace \(destination.lastPathComponent).")
                        }
                        self.removeTracking(download, id: id)
                        completionHandler(nil)
                        return
                    }
                }
                self.update(id) {
                    $0.filename = destination.lastPathComponent
                    $0.destinationURL = destination
                    $0.status = .downloading
                }
                completionHandler(destination)
            }
        }
    }

    func downloadDidFinish(_ download: WKDownload) {
        guard let id = id(for: download) else { return }
        update(id) { $0.status = .finished }
        removeTracking(download, id: id)
    }

    func download(
        _ download: WKDownload,
        didFailWithError error: Error,
        resumeData: Data?
    ) {
        guard let id = id(for: download) else { return }
        if items.first(where: { $0.id == id })?.status != .cancelled {
            update(id) { $0.status = .failed(error.localizedDescription) }
        }
        removeTracking(download, id: id)
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
