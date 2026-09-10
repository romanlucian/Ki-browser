import LimeghostCore
import LimeghostShared
import SwiftUI

struct AIToolStartPage: View {
    @ObservedObject var store: BrowserDataStore
    let openTool: (AIToolListing) -> Void
    let openSource: (AIToolListing, URL) -> Void
    /// Opening one of the outside references. Its own door, so it makes room
    /// for the page like every other door in the app.
    let openReference: (AIFieldReference) -> Void

    @State private var selectedCategory: AIToolCategory?
    @State private var toolSearch = ""
    @State private var showsAllTools = false
    @State private var showsRecommendationMethod = false

    private var visibleTools: [AIToolListing] {
        guard selectedCategory != nil || showsAllTools || !toolSearch.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return []
        }
        return AIToolCatalog.filtered(category: selectedCategory, query: toolSearch)
    }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [LimeghostTheme.bg0, LimeghostTheme.bg1],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    header
                    catalogStatus
                    recommendationMethod
                    toolSearchField
                    categoryFilters
                    toolShelf
                    fieldNotes
                    catalogGrid
                    catalogBoundary
                }
                .frame(maxWidth: 1_120, alignment: .leading)
                .padding(.horizontal, 30)
                .padding(.vertical, 30)
                .frame(maxWidth: .infinity)
            }
        }
        .accessibilityLabel("Limeghost AI tool guide")
    }

    private var catalogStatus: some View {
        HStack(spacing: 8) {
            // The build identifier ("2026.08.24.1") used to lead this row. It
            // is a developer's string on a page written for people who do not
            // have one, and the sentence beside it already makes the freshness
            // claim in words.
            Label("Links and labels checked", systemImage: "checkmark.seal")
            Text(
                AIToolCatalog.release.lastChecked,
                format: .dateTime.month(.abbreviated).day().year()
            )
            Spacer(minLength: 8)
            Button("How recommendations work") {
                withAnimation(.easeInOut(duration: 0.16)) {
                    showsRecommendationMethod.toggle()
                }
            }
            .buttonStyle(.plain)
            .foregroundStyle(LimeghostTheme.accent)
        }
        .font(.system(size: 11, weight: .medium))
        .foregroundStyle(LimeghostTheme.textSecondary)
        .padding(.horizontal, 4)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 20) {
            HStack(alignment: .top, spacing: 16) {
                // The real mark. A 30-point serif capital C stood here —
                // Clearframe's initial, left behind by the August 31, 2026
                // rename — beside a badge claiming the page is an honest guide.
                // A guard against exactly that had existed since September 1,
                // but it read `OnboardingView.swift` alone.
                BrandMark(size: 34)
                    .frame(width: 58, height: 58)
                    .background(
                        LimeghostTheme.accentDimStrong,
                        in: RoundedRectangle(cornerRadius: LimeghostTheme.radius18, style: .continuous)
                    )

                VStack(alignment: .leading, spacing: 7) {
                    Text("LIMEGHOST GUIDE")
                        .font(LimeghostTheme.metaFont)
                        .tracking(LimeghostTheme.metaTracking)
                        .foregroundStyle(LimeghostTheme.textSecondary)
                    Text("Choose the right AI\nfor the job.")
                        .font(.system(size: 38, weight: .bold, design: .serif))
                        .tracking(-1.2)
                        .foregroundStyle(LimeghostTheme.textPrimary)
                    Text("A small, practical starting point—not a live ranking.")
                        .font(.system(size: 13))
                        .foregroundStyle(LimeghostTheme.textBody)
                }
            }

            Spacer(minLength: 12)

            Label("Local guide · official links", systemImage: "checkmark.shield")
                .font(.system(size: 11, weight: .semibold))
                .fixedSize()
                .foregroundStyle(LimeghostTheme.accent)
                .padding(.horizontal, 12)
                .frame(height: 32)
                .background(LimeghostTheme.accentDim, in: Capsule())
                .overlay(Capsule().stroke(LimeghostTheme.accent.opacity(0.3)))
        }
    }

    /// The same field bookmarks and history draw, at this page's width.
    ///
    /// It was a private copy: same job, its own height, its own fill, its own
    /// two hairlines, none of them tokens. A second implementation is how the
    /// two drift, and this one had already drifted.
    private var toolSearchField: some View {
        HomeSearchField(
            placeholder: "Find an AI tool or task",
            text: $toolSearch,
            maximumWidth: .infinity
        )
    }

    private var categoryFilters: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(AIToolCategory.allCases) { category in
                    CategoryChip(
                        title: category.rawValue,
                        symbol: category.symbolName,
                        selected: selectedCategory == category,
                        action: {
                            selectedCategory = category
                            showsAllTools = false
                        }
                    )
                }
                CategoryChip(
                    title: "All Tools",
                    symbol: "square.grid.2x2",
                    selected: selectedCategory == nil && showsAllTools,
                    action: {
                        selectedCategory = nil
                        showsAllTools = true
                    }
                )
            }
        }
    }

    /// The tools this reader has opened, in the order their row holds them.
    private var shelfTools: [AIToolListing] {
        store.aiToolShelf.toolIDs.compactMap { id in
            AIToolCatalog.tools.first { $0.id == id }
        }
    }

    /// What a reader sees before they have opened anything. The catalog already
    /// marks a few tools per task as a sensible place to begin, and those are
    /// better company on a first run than six empty squares.
    private var startingPoints: [AIToolListing] {
        AIToolCatalog.tools
            .filter { !$0.recommendations.isEmpty }
            .prefix(AIToolShelf.defaultCapacity)
            .map { $0 }
    }

    /// The row only belongs on the page's own front, not over search results or
    /// inside a chosen task, where it would compete with the answer the reader asked for.
    @ViewBuilder
    private var toolShelf: some View {
        if selectedCategory == nil && !showsAllTools && toolSearch.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let tools = shelfTools.isEmpty ? startingPoints : shelfTools
            let isOwnRow = !shelfTools.isEmpty
            if !tools.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text(isOwnRow ? "YOUR TOOLS" : "GOOD PLACES TO START")
                        .font(LimeghostTheme.metaFont)
                        .tracking(LimeghostTheme.metaTracking)
                        .foregroundStyle(LimeghostTheme.textSecondary)
                    LazyVGrid(
                        columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 6),
                        spacing: 12
                    ) {
                        ForEach(tools) { tool in
                            ShelfToolButton(
                                tool: tool,
                                isPinned: store.aiToolShelf.isPinned(tool.id),
                                canManage: isOwnRow,
                                open: { openTool(tool) },
                                togglePin: {
                                    store.setAIToolPinned(tool.id, pinned: !store.aiToolShelf.isPinned(tool.id))
                                },
                                remove: { store.removeAITool(tool.id) }
                            )
                        }
                    }
                }
                .padding(20)
                .startSurfaceCard()
            }
        }
    }

    /// Three dated facts and the places that hold the live numbers.
    ///
    /// Deliberately trends and not ranks. A leaderboard position is stale
    /// within days, and this app only changes when somebody reinstalls it, so
    /// a rank compiled in here would be a confident lie most of the time —
    /// which is the judgment layer this product removed on August 30, 2026.
    /// A growth rate measured over fifteen years is still true next year.
    ///
    /// The figures are quoted from Epoch AI under Creative Commons
    /// Attribution; the credit is the licence, so it is drawn, not optional.
    @ViewBuilder
    private var fieldNotes: some View {
        if selectedCategory == nil && !showsAllTools && toolSearch.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            VStack(alignment: .leading, spacing: 16) {
                Text("HOW FAST THIS IS MOVING")
                    .font(LimeghostTheme.metaFont)
                    .tracking(LimeghostTheme.metaTracking)
                    .foregroundStyle(LimeghostTheme.textSecondary)

                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 240, maximum: 420), spacing: 16)],
                    alignment: .leading,
                    spacing: 16
                ) {
                    ForEach(AIFieldNotes.notes) { note in
                        VStack(alignment: .leading, spacing: 5) {
                            Text(note.figure)
                                .font(.system(size: 22, weight: .bold, design: .serif))
                                .foregroundStyle(LimeghostTheme.accent)
                            Text(note.measure)
                                .font(.system(size: 13))
                                .foregroundStyle(LimeghostTheme.textBody)
                                .fixedSize(horizontal: false, vertical: true)
                            Text(note.meaning)
                                .font(.system(size: 11))
                                .foregroundStyle(LimeghostTheme.textTertiary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }

                Divider().overlay(LimeghostTheme.hairline2)

                VStack(alignment: .leading, spacing: 9) {
                    Text("WHERE THE LIVE NUMBERS ARE")
                        .font(LimeghostTheme.microFont)
                        .tracking(LimeghostTheme.microTracking)
                        .foregroundStyle(LimeghostTheme.textTertiary)
                    ForEach(AIFieldNotes.references) { reference in
                        Button { openReference(reference) } label: {
                            HStack(alignment: .firstTextBaseline, spacing: 7) {
                                Image(systemName: "arrow.up.right")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundStyle(LimeghostTheme.accent)
                                Text(reference.name)
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(LimeghostTheme.textPrimary)
                                Text(reference.summary)
                                    .font(.system(size: 11))
                                    .foregroundStyle(LimeghostTheme.textTertiary)
                                    .lineLimit(1)
                                Spacer(minLength: 4)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .help("Open \(reference.name) in this tab")
                    }
                }

                // Says who measured this and when. Limeghost took none of these
                // numbers and does not rank anything — the page has to be as
                // plain about that here as it is about the catalog.
                Text("Figures published by Epoch AI under CC BY 4.0 and quoted here; checked \(AIFieldNotes.lastChecked.formatted(.dateTime.month(.abbreviated).day().year())). Limeghost does not measure or rank models.")
                    .font(.caption)
                    .foregroundStyle(LimeghostTheme.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .startSurfaceCard()
        }
    }

    @ViewBuilder
    private var catalogGrid: some View {
        if selectedCategory == nil && !showsAllTools && toolSearch.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Start with what you want to do")
                    .font(.system(size: 20, weight: .bold, design: .serif))
                    .foregroundStyle(LimeghostTheme.textPrimary)
                Text("Choose one task above. Limeghost will show a small set of useful paths and explain why each may fit.")
                    .font(.system(size: 13))
                    .foregroundStyle(LimeghostTheme.textBody)
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .startSurfaceCard()
        } else if visibleTools.isEmpty {
            // `ContentUnavailableView` was the only system-drawn empty state
            // in the app — its own icon size, type scale and layout, none of
            // which `LimeghostTheme` can reach. Bookmarks and history both say
            // this in the app's own voice.
            HomeEmptyNote("No tool in this catalog matches “\(toolSearch)”. Try another task, or show All Tools.")
        } else {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 238, maximum: 340), spacing: 14)],
                alignment: .leading,
                spacing: 14
            ) {
                ForEach(visibleTools) { tool in
                    AIToolCard(
                        tool: tool,
                        recommendation: tool.recommendation(for: selectedCategory),
                        open: { openTool(tool) },
                        openSource: { sourceURL in openSource(tool, sourceURL) }
                    )
                }
            }
        }
    }

    /// What "How recommendations work" opens.
    ///
    /// It used to live at the very bottom of the page, inside the boundary
    /// block, while the button that toggles it sits second from the top. With
    /// the search field, the filters, the tool row and a full grid of cards in
    /// between, pressing the button appeared to do nothing at all. A
    /// disclosure has to open where it was asked for.
    @ViewBuilder
    private var recommendationMethod: some View {
        if showsRecommendationMethod {
            VStack(alignment: .leading, spacing: 6) {
                Text("How recommendations work")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(LimeghostTheme.textPrimary)
                Text("Badges apply only to the selected task and this small catalog. They are editor judgments based on a tool’s documented focus, breadth, and broad access path—not Limeghost testing, a universal winner, live price monitoring, or provider payment. The official source beside a badge shows the product page used for its rationale. Reviews are manual and ship with app updates.")
                    .font(.caption)
                    .foregroundStyle(LimeghostTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Free to Try and Paid Plan are broad orientation labels. Limits, accounts, features, regions, and terms can change at any time.")
                    .font(.caption)
                    .foregroundStyle(LimeghostTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .startSurfaceCard()
            .transition(.opacity.combined(with: .move(edge: .top)))
        }
    }

    private var catalogBoundary: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("Before you open a tool")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(LimeghostTheme.textPrimary)
            Text("Limeghost does not rank these services live, share your current page or prompt, or receive payment when you open a card. Each provider controls accounts, plans, country availability, data use, and terms; check its official site before relying on a feature or access hint.")
                .font(.caption)
                .foregroundStyle(LimeghostTheme.textSecondary)
            // Says the thing the rest of this block only implies: that naming
            // these products is how a directory refers to them, not a claim of
            // any relationship. Two of the makers whose published policies
            // permit being named — Midjourney and Canva — ask for exactly this
            // notice in return.
            Text("Limeghost is independent: it is not affiliated with, endorsed by, or sponsored by any listed provider. All product and company names are trademarks of their respective owners.")
                .font(.caption)
                .foregroundStyle(LimeghostTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .startSurfaceCard()
    }
}

private struct CategoryChip: View {
    let title: String
    let symbol: String
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .font(.system(size: 11, weight: .semibold))
                .padding(.horizontal, 12)
                .frame(height: 34)
                .background(selected ? LimeghostTheme.accent : LimeghostTheme.bg2, in: Capsule())
                .foregroundStyle(selected ? LimeghostTheme.onAccent : LimeghostTheme.textBody)
                .overlay(Capsule().stroke(selected ? Color.clear : LimeghostTheme.hairline2))
        }
        .buttonStyle(.plain)
    }
}

private struct AIToolCard: View {
    let tool: AIToolListing
    let recommendation: AIToolRecommendation?
    let open: () -> Void
    let openSource: (URL) -> Void

    private var accent: Color { tool.markAccent }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: open) {
                cardContent
            }
            .buttonStyle(.plain)
            .focusable(true)
            .help("Open \(tool.name) official website")
            .accessibilityLabel("Open \(tool.name), best for \(tool.bestFor)")
            .accessibilityHint("Opens the official website in the current Limeghost tab")

            // Without this the footer follows the text upward and the card's
            // remaining height falls away underneath it, so four cards in a
            // row showed their access label at four different heights.
            Spacer(minLength: 0)

            Divider().overlay(LimeghostTheme.hairline2)

            HStack(spacing: 8) {
                Text(tool.access.rawValue)
                    .font(LimeghostTheme.microFont)
                    .tracking(LimeghostTheme.microTracking)
                    .foregroundStyle(LimeghostTheme.textSecondary)
                    .padding(.horizontal, 8)
                    .frame(height: 23)
                    .background(LimeghostTheme.bg3, in: Capsule())

                Spacer(minLength: 4)

                if let recommendation {
                    Button {
                        openSource(recommendation.officialSourceURL)
                    } label: {
                        Label("Official source", systemImage: "arrow.up.right")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(LimeghostTheme.textSecondary)
                    .help("Open the official product source for this task recommendation")
                } else {
                    Button(action: open) {
                        Label("Official site", systemImage: "arrow.up.right")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(LimeghostTheme.textSecondary)
                }
            }
            .padding(.horizontal, 15)
            .padding(.vertical, 10)
        }
        .frame(maxWidth: .infinity, minHeight: recommendation == nil ? 190 : 230, alignment: .topLeading)
        .startSurfaceCard()
    }

    private var cardContent: some View {
        VStack(alignment: .leading, spacing: 13) {
            if let recommendation {
                HStack(spacing: 6) {
                    Text(recommendation.badge.rawValue.uppercased())
                        .font(LimeghostTheme.microFont)
                        .tracking(LimeghostTheme.microTracking)
                    Text("·")
                    Text(recommendation.category.rawValue.uppercased())
                        .font(LimeghostTheme.microFont)
                        .tracking(LimeghostTheme.microTracking)
                }
                .foregroundStyle(LimeghostTheme.bg0)
                .padding(.horizontal, 8)
                .frame(height: 22)
                .background(accent, in: Capsule())
            }

            HStack(alignment: .top, spacing: 11) {
                AIToolMark(tool: tool, accent: accent)

                VStack(alignment: .leading, spacing: 3) {
                    Text(tool.name)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(LimeghostTheme.textPrimary)
                    Text("\(tool.maker) · \(tool.kind)")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(LimeghostTheme.textTertiary)
                        .lineLimit(1)
                }

                Spacer(minLength: 4)
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(LimeghostTheme.textTertiary)
            }

            VStack(alignment: .leading, spacing: 5) {
                Text(recommendation == nil ? "BEST FOR" : "WHY THIS TASK")
                    .font(LimeghostTheme.microFont)
                    .tracking(LimeghostTheme.microTracking)
                    .foregroundStyle(accent.opacity(0.9))
                Text(recommendation?.rationale ?? tool.bestFor)
                    .font(.system(size: 13))
                    .foregroundStyle(LimeghostTheme.textBody)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(15)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .contentShape(Rectangle())
    }
}

/// A tool's mark on the AI home: the site's real icon once Limeghost has one,
/// and the catalog's monogram until then.
///
/// No logo is bundled with the app. The icon is the one captured on a visit
/// like any other — so a tool the reader has opened is shown as itself, and one
/// they have not keeps the designed monogram rather than an empty square. That
/// keeps this page under the same rule as the rest of the browser: an icon
/// comes from a visit, never from a file shipped alongside somebody else's
/// trademark and never from a service asked about it.
extension AIToolListing {
    /// The colour this tool's mark is drawn in, wherever it appears.
    ///
    /// Retuned for the Halo palette (B7): the default bucket matches
    /// `LimeghostTheme.accent` — the old lime literal it used to hardcode — and
    /// the ChatGPT/DeepSeek/Runway teal shifted further toward cyan so it stays
    /// visually distinct from that mint default instead of echoing it.
    ///
    /// It lives here rather than inside the card because the row on the page's
    /// front draws the same marks. Two copies of this table would drift, and a
    /// tool would be one colour in the row and another in its own card.
    var markAccent: Color {
        switch id {
        case "chatgpt", "deepseek", "runway": return Color(red: 0.24, green: 0.75, blue: 0.78)
        case "claude", "mistral", "firefly": return Color(red: 0.95, green: 0.58, blue: 0.38)
        case "gemini", "qwen", "google-translate", "veo": return Color(red: 0.42, green: 0.64, blue: 0.98)
        case "grok", "midjourney": return Color(red: 0.76, green: 0.78, blue: 0.82)
        case "kimi", "perplexity": return Color(red: 0.60, green: 0.82, blue: 0.95)
        case "canva", "deepl", "seedance": return Color(red: 0.73, green: 0.55, blue: 0.98)
        default: return LimeghostTheme.accent
        }
    }
}

struct AIToolMark: View {
    let tool: AIToolListing
    let accent: Color
    var size: CGFloat = 40
    @Environment(\.faviconStore) private var store

    var body: some View {
        Group {
            if let store {
                CapturedAIToolMark(store: store, tool: tool, accent: accent, size: size)
            } else {
                AIToolMonogram(tool: tool, accent: accent, size: size)
            }
        }
        .frame(width: size, height: size)
        // The card already names the tool and its maker.
        .accessibilityHidden(true)
    }
}

/// Split out so the mark redraws the moment a capture completes: an
/// `@ObservedObject` needs a concrete view identity to subscribe from.
private struct CapturedAIToolMark: View {
    @ObservedObject var store: FaviconStore
    let tool: AIToolListing
    let accent: Color
    let size: CGFloat

    var body: some View {
        if let host = tool.officialURL.host, let icon = store.icon(forHost: host) {
            // `.resizable()` plus the explicit `.frame()` below decide the
            // on-screen size; the scale here never reaches the display.
            Image(decorative: icon, scale: 2)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .frame(width: size, height: size)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        } else {
            AIToolMonogram(tool: tool, accent: accent, size: size)
        }
    }
}

private struct AIToolMonogram: View {
    let tool: AIToolListing
    let accent: Color
    let size: CGFloat

    var body: some View {
        Text(tool.monogram)
            .font(.system(size: size * 0.3, weight: .bold, design: .rounded))
            .foregroundStyle(LimeghostTheme.bg0)
            .frame(width: size, height: size)
            .background(accent, in: RoundedRectangle(cornerRadius: 12))
    }
}

/// One tile on the reader's row. Secondary-click carries the two things a reader
/// might want of it — keep this one where it is, or take it off — so the tile
/// stays a single target and nothing hovers into view over it.
private struct ShelfToolButton: View {
    let tool: AIToolListing
    let isPinned: Bool
    let canManage: Bool
    let open: () -> Void
    let togglePin: () -> Void
    let remove: () -> Void

    var body: some View {
        Button(action: open) {
            VStack(spacing: 6) {
                ZStack(alignment: .topTrailing) {
                    // The same mark the tool's own card draws, so a tool looks
                    // like itself in both places — and becomes its real logo
                    // here too, once a visit has captured one.
                    AIToolMark(tool: tool, accent: tool.markAccent, size: 44)
                    if isPinned {
                        Image(systemName: "pin.fill")
                            .font(.system(size: 8))
                            .foregroundStyle(LimeghostTheme.accent)
                            .offset(x: 4, y: -4)
                    }
                }
                Text(tool.name)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(LimeghostTheme.textBody)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        .help(tool.bestFor)
        .contextMenu {
            if canManage {
                Button(isPinned ? "Unpin" : "Pin to this row", action: togglePin)
                Button("Remove from this row", role: .destructive, action: remove)
            }
        }
    }
}
