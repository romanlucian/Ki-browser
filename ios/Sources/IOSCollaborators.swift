import Combine
import UIKit
import WebKit
import LimeghostShared

/// The system pasteboard.
@MainActor
final class IOSClipboard: ClipboardWriting {
    func setString(_ string: String) {
        UIPasteboard.general.string = string
    }
}

/// Sharing a page. iOS has one share sheet and it takes the address directly,
/// so the two file-producing members have nothing to do in this version:
/// downloads are deliberately out of v1, and "save as" and "export PDF" are
/// both ways of producing a file.
@MainActor
enum IOSPageSharing: PageSharing {
    static func savePage(
        named suggestedName: String,
        archivedBy archive: @escaping (@escaping (Result<Data, Error>) -> Void) -> Void,
        completion: @escaping (Result<URL, Error>) -> Void
    ) {}

    static func exportPDF(
        named suggestedName: String,
        renderedBy render: @escaping (@escaping (Result<Data, Error>) -> Void) -> Void,
        completion: @escaping (Result<URL, Error>) -> Void
    ) {}

    static func share(_ url: URL) {
        let controller = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        guard let root = Self.rootViewController else { return }
        controller.popoverPresentationController?.sourceView = root.view
        root.present(controller, animated: true)
    }

    static var rootViewController: UIViewController? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }?
            .keyWindow?
            .rootViewController
    }
}

/// Downloads are deliberately not in v1: on iOS they are Files integration,
/// resumability and a list — a subsystem, not a button. The workspace only
/// needs the collaborator to exist.
@MainActor
final class NoDownloads: DownloadTracking {
    func track(_ download: WKDownload, sourceURL: URL?) {}
    let objectWillChange = ObservableObjectPublisher()
    func clearAllRecords() {}
}
