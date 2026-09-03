import Foundation

/// Saving, exporting, and sharing the page in front of somebody — a save
/// panel, a PDF export panel, and the system share sheet. All three are
/// AppKit today (`NSSavePanel`, `NSSharingServicePicker`) and stay in the app
/// target; `BrowserWorkspace` only starts them and reports back what
/// happened.
///
/// Static requirements, not instance ones: the macOS conformer,
/// `PageFileCommands`, is a caseless enum used only as a namespace, and
/// `BrowserWorkspace` holds its metatype rather than manufacturing an
/// instance nothing would ever use.
@MainActor
public protocol PageSharing {
    static func savePage(
        named suggestedName: String,
        archivedBy archive: @escaping (@escaping (Result<Data, Error>) -> Void) -> Void,
        completion: @escaping (Result<URL, Error>) -> Void
    )

    static func exportPDF(
        named suggestedName: String,
        renderedBy render: @escaping (@escaping (Result<Data, Error>) -> Void) -> Void,
        completion: @escaping (Result<URL, Error>) -> Void
    )

    /// Offers the address to the apps the person has, through the system's
    /// own picker. The macOS conformer resolves its own anchor window —
    /// `NSView` cannot appear in this target — which is exactly what it did
    /// when no view was given before this seam existed.
    static func share(_ url: URL)
}

/// Puts text on the system clipboard. `NSPasteboard` stays in the app
/// target; this is the one member Copy for AI and Reader's own Copy button
/// need from it.
@MainActor
public protocol ClipboardWriting: AnyObject {
    func setString(_ string: String)
}
