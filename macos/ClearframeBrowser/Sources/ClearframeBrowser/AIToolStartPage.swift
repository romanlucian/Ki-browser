import ClearframeCore
import SwiftUI

struct AIToolStartPage: View {
    let openTool: (AIToolListing) -> Void
    let openSource: (AIToolListing, URL) -> Void

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
                colors: [ClearframeTheme.bg0, ClearframeTheme.bg1],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    header
                    catalogStatus
                    toolSearchField
                    categoryFilters
                    catalogGrid
                    catalogBoundary
                }
                .frame(maxWidth: 1_120, alignment: .leading)
                .padding(.horizontal, 30)
                .padding(.vertical, 30)
                .frame(maxWidth: .infinity)
            }
        }
        .accessibilityLabel("Clearframe AI tool guide")
    }

    private var catalogStatus: some View {
        HStack(spacing: 8) {
            Label("Catalog \(AIToolCatalog.release.version)", systemImage: "checkmark.seal")
            Text("·")
            Text("Links and labels checked")
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
            .foregroundStyle(ClearframeTheme.accent)
        }
        .font(.system(size: 10.5, weight: .medium))
        .foregroundStyle(Color.white.opacity(0.56))
        .padding(.horizontal, 4)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 20) {
            HStack(alignment: .top, spacing: 16) {
                Text("C")
                    .font(.system(size: 30, weight: .bold, design: .serif))
                    .foregroundStyle(ClearframeTheme.accent)
                    .frame(width: 58, height: 58)
                    .background(ClearframeTheme.accentDimStrong, in: RoundedRectangle(cornerRadius: 17))

                VStack(alignment: .leading, spacing: 7) {
                    Text("CLEARFRAME GUIDE")
                        .font(.system(size: 10, weight: .bold))
                        .tracking(1.8)
                        .foregroundStyle(ClearframeTheme.textSecondary)
                    Text("Choose the right AI\nfor the job.")
                        .font(.system(size: 38, weight: .bold, design: .serif))
                        .tracking(-1.2)
                        .foregroundStyle(.white)
                    Text("A small, practical starting point—not a live ranking.")
                        .font(.callout)
                        .foregroundStyle(Color.white.opacity(0.66))
                }
            }

            Spacer(minLength: 12)

            Label("Local guide · official links", systemImage: "checkmark.shield")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(ClearframeTheme.accent)
                .padding(.horizontal, 12)
                .frame(height: 32)
                .background(ClearframeTheme.accentDim, in: Capsule())
                .overlay(Capsule().stroke(ClearframeTheme.accent.opacity(0.3)))
        }
    }

    private var toolSearchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(Color.white.opacity(0.56))
            TextField("Find an AI tool or task", text: $toolSearch)
                .textFieldStyle(.plain)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.white)
            if !toolSearch.isEmpty {
                Button { toolSearch = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Color.white.opacity(0.42))
                }
                .buttonStyle(.plain)
                .help("Clear tool search")
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 42)
        .background(Color.white.opacity(0.075), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.11)))
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

    @ViewBuilder
    private var catalogGrid: some View {
        if selectedCategory == nil && !showsAllTools && toolSearch.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Label("Start with what you want to do", systemImage: "arrow.up.circle.fill")
                    .font(.system(size: 18, weight: .bold, design: .serif))
                Text("Choose one task above. Clearframe will show a small set of useful paths and explain why each may fit.")
                    .font(.callout)
                    .foregroundStyle(ClearframeTheme.textSecondary)
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(ClearframeTheme.bg2, in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(ClearframeTheme.hairline2))
        } else if visibleTools.isEmpty {
            ContentUnavailableView(
                "No matching tools",
                systemImage: "magnifyingglass",
                description: Text("Try another task or show All Tools.")
            )
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, minHeight: 260)
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

    private var catalogBoundary: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("Before you open a tool")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(ClearframeTheme.textPrimary)
            Text("Clearframe does not rank these services live, share your current page or prompt, or receive payment when you open a card. Each provider controls accounts, plans, country availability, data use, and terms; check its official site before relying on a feature or access hint.")
                .font(.caption)
                .foregroundStyle(ClearframeTheme.textSecondary)
            // Says the thing the rest of this block only implies: that naming
            // these products is how a directory refers to them, not a claim of
            // any relationship. Two of the makers whose published policies
            // permit being named — Midjourney and Canva — ask for exactly this
            // notice in return.
            Text("Clearframe is independent: it is not affiliated with, endorsed by, or sponsored by any listed provider. All product and company names are trademarks of their respective owners.")
                .font(.caption)
                .foregroundStyle(ClearframeTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            if showsRecommendationMethod {
                Divider().overlay(ClearframeTheme.hairline2)
                VStack(alignment: .leading, spacing: 6) {
                    Text("How recommendations work")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(ClearframeTheme.textPrimary)
                    Text("Badges apply only to the selected task and this small catalog. They are editor judgments based on a tool’s documented focus, breadth, and broad access path—not Clearframe testing, a universal winner, live price monitoring, or provider payment. The official source beside a badge shows the product page used for its rationale. Reviews are manual and ship with app updates.")
                        .font(.caption)
                        .foregroundStyle(ClearframeTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("Free to Try and Paid Plan are broad orientation labels. Limits, accounts, features, regions, and terms can change at any time.")
                        .font(.caption)
                        .foregroundStyle(ClearframeTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(16)
        .background(ClearframeTheme.bg2, in: RoundedRectangle(cornerRadius: 13))
        .overlay(RoundedRectangle(cornerRadius: 13).stroke(ClearframeTheme.hairline1))
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
                .background(selected ? ClearframeTheme.accent : Color.white.opacity(0.065), in: Capsule())
                .foregroundStyle(selected ? ClearframeTheme.onAccent : Color.white.opacity(0.75))
                .overlay(Capsule().stroke(selected ? Color.clear : Color.white.opacity(0.09)))
        }
        .buttonStyle(.plain)
    }
}

private struct AIToolCard: View {
    let tool: AIToolListing
    let recommendation: AIToolRecommendation?
    let open: () -> Void
    let openSource: (URL) -> Void

    // Retuned for the Halo palette (B7): the default bucket now matches
    // ClearframeTheme.accent — the old lime literal it used to hardcode —
    // and the ChatGPT/DeepSeek/Runway teal shifted further toward cyan so it
    // stays visually distinct from that mint default instead of echoing it.
    private var accent: Color {
        switch tool.id {
        case "chatgpt", "deepseek", "runway": return Color(red: 0.24, green: 0.75, blue: 0.78)
        case "claude", "mistral", "firefly": return Color(red: 0.95, green: 0.58, blue: 0.38)
        case "gemini", "qwen", "google-translate", "veo": return Color(red: 0.42, green: 0.64, blue: 0.98)
        case "grok", "midjourney": return Color(red: 0.76, green: 0.78, blue: 0.82)
        case "kimi", "perplexity": return Color(red: 0.60, green: 0.82, blue: 0.95)
        case "canva", "deepl", "seedance": return Color(red: 0.73, green: 0.55, blue: 0.98)
        default: return ClearframeTheme.accent
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: open) {
                cardContent
            }
            .buttonStyle(.plain)
            .focusable(true)
            .help("Open \(tool.name) official website")
            .accessibilityLabel("Open \(tool.name), best for \(tool.bestFor)")
            .accessibilityHint("Opens the official website in the current Clearframe tab")

            Divider().overlay(Color.white.opacity(0.08))

            HStack(spacing: 8) {
                Text(tool.access.rawValue)
                    .font(.system(size: 9.5, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.56))
                    .padding(.horizontal, 8)
                    .frame(height: 23)
                    .background(Color.white.opacity(0.055), in: Capsule())

                Spacer(minLength: 4)

                if let recommendation {
                    Button {
                        openSource(recommendation.officialSourceURL)
                    } label: {
                        Label("Official source", systemImage: "arrow.up.right")
                            .font(.system(size: 9.5, weight: .semibold))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.white.opacity(0.58))
                    .help("Open the official product source for this task recommendation")
                } else {
                    Button(action: open) {
                        Label("Official site", systemImage: "arrow.up.right")
                            .font(.system(size: 9.5, weight: .semibold))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.white.opacity(0.58))
                }
            }
            .padding(.horizontal, 15)
            .padding(.vertical, 10)
        }
        .frame(maxWidth: .infinity, minHeight: recommendation == nil ? 190 : 230, alignment: .topLeading)
        .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.white.opacity(0.1)))
    }

    private var cardContent: some View {
        VStack(alignment: .leading, spacing: 13) {
            if let recommendation {
                HStack(spacing: 6) {
                    Text(recommendation.badge.rawValue.uppercased())
                        .font(.system(size: 8.5, weight: .bold))
                        .tracking(0.65)
                    Text("·")
                    Text(recommendation.category.rawValue.uppercased())
                        .font(.system(size: 8.5, weight: .semibold))
                }
                .foregroundStyle(Color.black.opacity(0.7))
                .padding(.horizontal, 8)
                .frame(height: 22)
                .background(accent, in: Capsule())
            }

            HStack(alignment: .top, spacing: 11) {
                AIToolMark(tool: tool, accent: accent)

                VStack(alignment: .leading, spacing: 3) {
                    Text(tool.name)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.white)
                    Text("\(tool.maker) · \(tool.kind)")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Color.white.opacity(0.5))
                        .lineLimit(1)
                }

                Spacer(minLength: 4)
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Color.white.opacity(0.46))
            }

            VStack(alignment: .leading, spacing: 5) {
                Text(recommendation == nil ? "BEST FOR" : "WHY THIS TASK")
                    .font(.system(size: 9, weight: .bold))
                    .tracking(1.1)
                    .foregroundStyle(accent.opacity(0.9))
                Text(recommendation?.rationale ?? tool.bestFor)
                    .font(.system(size: 12))
                    .foregroundStyle(Color.white.opacity(0.76))
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(15)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .contentShape(Rectangle())
    }
}

/// A tool's mark on the AI home: the site's real icon once Clearframe has one,
/// and the catalog's monogram until then.
///
/// No logo is bundled with the app. The icon is the one captured on a visit
/// like any other — so a tool the reader has opened is shown as itself, and one
/// they have not keeps the designed monogram rather than an empty square. That
/// keeps this page under the same rule as the rest of the browser: an icon
/// comes from a visit, never from a file shipped alongside somebody else's
/// trademark and never from a service asked about it.
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
            Image(nsImage: icon)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fill)
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
            .foregroundStyle(Color.black.opacity(0.72))
            .frame(width: size, height: size)
            .background(accent, in: RoundedRectangle(cornerRadius: 12))
    }
}
