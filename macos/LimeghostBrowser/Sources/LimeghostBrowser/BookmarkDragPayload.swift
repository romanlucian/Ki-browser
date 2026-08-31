import Foundation

/// How a folder describes itself while being dragged.
///
/// The bar's drops already carry a `URL`, because a page link and a saved
/// bookmark both are one. A folder is not, so it travels as a URL with a scheme
/// of its own: one drop destination still handles everything landing on a chip,
/// and there is no second payload type to arbitrate between.
///
/// The scheme is deliberately not a web one. `WebURLPolicy` refuses it, so a
/// folder reference dropped somewhere that saves bookmarks cannot quietly
/// become one.
enum BookmarkDragPayload {
    static let folderScheme = "limeghost-folder"

    static func folderURL(_ id: UUID) -> URL? {
        URL(string: "\(folderScheme)://\(id.uuidString)")
    }

    /// The folder a dragged URL refers to, or nil if it refers to a page.
    static func folderID(from url: URL) -> UUID? {
        guard url.scheme == folderScheme else { return nil }
        let raw = url.host ?? url.absoluteString.replacingOccurrences(of: "\(folderScheme)://", with: "")
        return UUID(uuidString: raw)
    }
}
