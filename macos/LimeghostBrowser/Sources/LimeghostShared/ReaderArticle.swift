import LimeghostCore

/// One page as Limeghost reads it.
///
/// Built only from `LocalAnalysisEngine`, and deliberately holding the exact
/// string `clipboardPayload` produces rather than a second rendering of the
/// same page. Reader's whole claim is that what somebody sees here is what an
/// assistant receives, and the only way to keep that true over time is for both
/// to read one value.
///
/// Lives here rather than beside `ReaderView` because `BrowserTab` holds one
/// per tab: a model `BrowserWorkspace` needs, not a view. `ReaderView` itself
/// — the styled rendering — stays in the app target and imports this type.
public struct ReaderArticle: Equatable {
    public let title: String
    public let url: String
    public let host: String
    /// `readableText` split at the block boundaries the extractor emitted.
    public let paragraphs: [String]
    public let words: Int
    public let readingMinutes: Int
    /// What share of the page's reading text the chosen container held. `0`
    /// means no article was found and this is the whole document.
    public let confidence: Double?
    public let isListing: Bool
    /// Exactly what Copy for AI puts on the clipboard, header and all.
    public let clipboardPayload: String

    public init?(page: PageSnapshot) {
        guard let payload = LocalAnalysisEngine.clipboardPayload(page: page) else { return nil }
        let text = LocalAnalysisEngine.readableText(page: page)
        let blocks = text
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        guard !blocks.isEmpty else { return nil }

        title = page.title
        url = page.url
        host = page.hostname
        paragraphs = blocks
        words = LocalAnalysisEngine.wordCount(of: text)
        readingMinutes = LocalAnalysisEngine.readingTime(wordCount: words)
        confidence = page.extractionConfidence
        isListing = LocalAnalysisEngine.assessStructure(page: page) == .listing
        clipboardPayload = payload
    }

    /// The notice Copy for AI shows after writing to the clipboard, or nil when
    /// there is nothing worth interrupting for. It lives here so the condition
    /// is stated once and Reader's own warning cannot drift away from it.
    public var copyNotice: String? {
        if let confidence, confidence < 0.5 {
            return confidence == 0
                ? "Copied \(words) words — but Limeghost could not find an article here, so this is the whole page, menus included."
                : "Copied \(words) words — but Limeghost is not confident it found the article on this page."
        }
        if isListing {
            return "Copied \(words) words — note this page lists many articles rather than being one."
        }
        return nil
    }

    /// The same fact as `copyNotice`, phrased to stand on its own in Reader's
    /// header rather than to follow a word count.
    public var extractionWarning: String? {
        if let confidence, confidence < 0.5 {
            return confidence == 0
                ? "Limeghost could not find an article here, so this is the whole page, menus included."
                : "Limeghost is not confident it found the article on this page."
        }
        if isListing {
            return "This page lists many articles rather than being one piece of writing."
        }
        return nil
    }
}
