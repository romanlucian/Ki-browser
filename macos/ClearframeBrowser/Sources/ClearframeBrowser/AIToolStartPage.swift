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
                colors: [
                    Color(red: 0.035, green: 0.095, blue: 0.072),
                    Color(red: 0.055, green: 0.075, blue: 0.065),
                    Color(nsColor: .windowBackgroundColor)
                ],
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
            Text("Last checked")
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
            .foregroundStyle(Color(red: 0.79, green: 0.92, blue: 0.52))
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
                    .foregroundStyle(Color(red: 0.83, green: 0.96, blue: 0.46))
                    .frame(width: 58, height: 58)
                    .background(Color(red: 0.07, green: 0.32, blue: 0.24), in: RoundedRectangle(cornerRadius: 17))

                VStack(alignment: .leading, spacing: 7) {
                    Text("CLEARFRAME GUIDE")
                        .font(.system(size: 10, weight: .bold))
                        .tracking(1.8)
                        .foregroundStyle(Color(red: 0.65, green: 0.82, blue: 0.71))
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
                .foregroundStyle(Color(red: 0.78, green: 0.90, blue: 0.82))
                .padding(.horizontal, 12)
                .frame(height: 32)
                .background(Color.white.opacity(0.075), in: Capsule())
                .overlay(Capsule().stroke(Color.white.opacity(0.1)))
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
                    .foregroundStyle(Color.white.opacity(0.68))
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.white.opacity(0.10)))
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
                .foregroundStyle(Color.white.opacity(0.8))
            Text("Clearframe does not rank these services live, share your current page or prompt, or receive payment when you open a card. Each provider controls accounts, plans, country availability, data use, and terms; check its official site before relying on a feature or access hint.")
                .font(.caption)
                .foregroundStyle(Color.white.opacity(0.54))
                .fixedSize(horizontal: false, vertical: true)

            if showsRecommendationMethod {
                Divider().overlay(Color.white.opacity(0.1))
                VStack(alignment: .leading, spacing: 6) {
                    Text("How recommendations work")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.82))
                    Text("Badges apply only to the selected task and this small catalog. They are editor judgments based on a tool’s documented focus, breadth, and broad access path—not Clearframe testing, a universal winner, live price monitoring, or provider payment. The official source beside a badge shows the product page used for its rationale. Reviews are manual and ship with app updates.")
                        .font(.caption)
                        .foregroundStyle(Color.white.opacity(0.58))
                        .fixedSize(horizontal: false, vertical: true)
                    Text("Free to Try and Paid Plan are broad orientation labels. Limits, accounts, features, regions, and terms can change at any time.")
                        .font(.caption)
                        .foregroundStyle(Color.white.opacity(0.58))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(16)
        .background(Color.black.opacity(0.16), in: RoundedRectangle(cornerRadius: 13))
        .overlay(RoundedRectangle(cornerRadius: 13).stroke(Color.white.opacity(0.07)))
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
                .background(selected ? Color(red: 0.76, green: 0.91, blue: 0.42) : Color.white.opacity(0.065), in: Capsule())
                .foregroundStyle(selected ? Color(red: 0.045, green: 0.13, blue: 0.095) : Color.white.opacity(0.75))
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

    private var accent: Color {
        switch tool.id {
        case "chatgpt", "deepseek", "runway": return Color(red: 0.31, green: 0.78, blue: 0.63)
        case "claude", "mistral", "firefly": return Color(red: 0.95, green: 0.58, blue: 0.38)
        case "gemini", "qwen", "google-translate", "veo": return Color(red: 0.42, green: 0.64, blue: 0.98)
        case "grok", "midjourney": return Color(red: 0.76, green: 0.78, blue: 0.82)
        case "kimi", "perplexity": return Color(red: 0.60, green: 0.82, blue: 0.95)
        case "canva", "deepl", "seedance": return Color(red: 0.73, green: 0.55, blue: 0.98)
        default: return Color(red: 0.76, green: 0.91, blue: 0.42)
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
                Text(tool.monogram)
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.black.opacity(0.72))
                    .frame(width: 40, height: 40)
                    .background(accent, in: RoundedRectangle(cornerRadius: 12))

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
