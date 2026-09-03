import LimeghostCore
import LimeghostShared
import SwiftUI

/// The page's own words, with the site's furniture removed.
///
/// Not a prettier rendering of the page: it is the extractor's output, drawn.
/// No images, no links, no reconstructed headings — adding any of those would
/// mean Reader and the assistant were looking at different things, and the one
/// thing this view is for is letting somebody see what the assistant will get.
///
/// It is also the only place extraction is visible at all. Everywhere else the
/// text goes straight to a clipboard, so a page the extractor reads badly used
/// to surface as a strange answer from an assistant with nothing to point at.
struct ReaderView: View {
    let article: ReaderArticle
    let copy: () -> Void
    let close: () -> Void

    /// Briefly true after a copy. The toolbar icon used to carry this
    /// confirmation and no longer exists, so it moved to the button that
    /// replaced it — still a changed glyph rather than a sentence, because a
    /// sentence on every copy is one nobody reads by the third time.
    @State private var didCopy = false

    /// The measure below is a reading column, not the window. Long lines are
    /// the thing reader modes exist to fix, and a paragraph the full width of a
    /// 2560-point display is worse to read than the page it replaced.
    private static let column: CGFloat = 680

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text(article.title)
                        .font(.system(size: 30, weight: .semibold))
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.bottom, 4)

                    ForEach(Array(article.paragraphs.enumerated()), id: \.offset) { _, paragraph in
                        Text(paragraph)
                            .font(.system(size: 16))
                            .lineSpacing(6)
                            .foregroundStyle(LimeghostTheme.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                            .textSelection(.enabled)
                    }
                }
                .frame(maxWidth: Self.column, alignment: .leading)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 32)
                .padding(.vertical, 36)
            }
        }
        .background(LimeghostTheme.bg1)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: "doc.plaintext")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(LimeghostTheme.accent)
                Text("Reader")
                    .font(.system(size: 13, weight: .semibold))
                Text(article.host)
                    .font(.system(size: 12))
                    .foregroundStyle(LimeghostTheme.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.middle)

                Spacer(minLength: 12)

                // Says what the assistant would receive, in the words the
                // clipboard header uses, so the two never describe the same
                // page differently.
                Text("\(article.words) words · \(article.readingMinutes) min")
                    .font(.system(size: 11))
                    .foregroundStyle(LimeghostTheme.textTertiary)

                Button {
                    copy()
                    didCopy = true
                    Task { @MainActor in
                        try? await Task.sleep(nanoseconds: 1_600_000_000)
                        didCopy = false
                    }
                } label: {
                    Label(
                        didCopy ? "Copied" : "Copy for AI",
                        systemImage: didCopy ? "checkmark" : "doc.on.doc"
                    )
                    .font(.system(size: 12, weight: .medium))
                }
                .buttonStyle(.borderless)
                .foregroundStyle(didCopy ? LimeghostTheme.accent : LimeghostTheme.textPrimary)
                .help("Copy this exact text, with its title and address, for pasting into an assistant (⇧⌘C)")

                Button(action: close) {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .semibold))
                }
                .buttonStyle(.borderless)
                .help("Close Reader and go back to the page")
                .accessibilityLabel("Close Reader")
            }

            if let warning = article.extractionWarning {
                HStack(alignment: .top, spacing: 7) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.orange)
                    Text(warning)
                        .font(.system(size: 11))
                        .foregroundStyle(LimeghostTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
        .background(LimeghostTheme.bg2)
    }
}
