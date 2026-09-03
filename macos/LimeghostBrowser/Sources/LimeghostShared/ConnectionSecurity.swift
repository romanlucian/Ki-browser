import LimeghostCore

/// How the connection to the page in front of the reader actually stands.
///
/// The scheme alone is not the answer: an `https://` page that pulled part of
/// itself over `http://` is not fully encrypted, and a lock over it would be a
/// claim Limeghost cannot back. WebKit answers that second half with
/// `hasOnlySecureContent`, so both facts are used and the chip and the popover
/// read from the same value. Kept as a plain derivation, like `ShieldState`, so
/// it can be tested without a web view.
///
/// Only the cases and `make(...)` live here: `BrowserSession` (which computes
/// this value on every navigation) is the reason this type has to be visible
/// from `LimeghostShared` at all. Its chrome-facing presentation --
/// `chromeIcon`, `tint`, and the rest -- stays behind in the app target's
/// `SiteInformationViews.swift`, as an extension, because it draws on
/// `ChromeIcon` and SwiftUI `Color`, neither of which this type needs for its
/// own job of describing what happened on the wire.
public enum ConnectionSecurity: Equatable {
    /// A Limeghost surface, not a website.
    case noPage
    /// An HTTPS page that has not committed yet. Until it does,
    /// `hasOnlySecureContent` still describes the document being replaced, so
    /// there is nothing truthful to say about this one's subresources.
    case checking
    case secure
    case mixedContent
    case notSecure

    public static func make(
        urlString: String,
        hasOnlySecureContent: Bool,
        hasCommittedNavigation: Bool
    ) -> ConnectionSecurity {
        guard let url = WebURLPolicy.validatedURL(urlString) else { return .noPage }
        guard url.scheme?.lowercased() == "https" else { return .notSecure }
        guard hasCommittedNavigation else { return .checking }
        return hasOnlySecureContent ? .secure : .mixedContent
    }
}
