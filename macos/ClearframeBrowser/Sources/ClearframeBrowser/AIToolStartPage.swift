import ClearframeCore
import SwiftUI

struct AIToolStartPage: View {
    let openTool: (AIToolListing) -> Void

    @State private var selectedCategory: AIToolCategory?
    @State private var toolSearch = ""

    private var visibleTools: [AIToolListing] {
        AIToolCatalog.filtered(category: selectedCategory, query: toolSearch)
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
                CategoryChip(
                    title: "All Tools",
                    symbol: "square.grid.2x2",
                    selected: selectedCategory == nil,
                    action: { selectedCategory = nil }
                )
                ForEach(AIToolCategory.allCases) { category in
                    CategoryChip(
                        title: category.rawValue,
                        symbol: category.symbolName,
                        selected: selectedCategory == category,
                        action: { selectedCategory = category }
                    )
                }
            }
        }
    }

    @ViewBuilder
    private var catalogGrid: some View {
        if visibleTools.isEmpty {
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
                    AIToolCard(tool: tool, open: { openTool(tool) })
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
    let open: () -> Void

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
        Button(action: open) {
            VStack(alignment: .leading, spacing: 13) {
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
                    Text("BEST FOR")
                        .font(.system(size: 9, weight: .bold))
                        .tracking(1.1)
                        .foregroundStyle(accent.opacity(0.9))
                    Text(tool.bestFor)
                        .font(.system(size: 12))
                        .foregroundStyle(Color.white.opacity(0.76))
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Text(tool.accessHint)
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.47))
                    .padding(.horizontal, 8)
                    .frame(height: 23)
                    .background(Color.white.opacity(0.055), in: Capsule())
                    .lineLimit(1)
            }
            .padding(15)
            .frame(maxWidth: .infinity, minHeight: 174, alignment: .topLeading)
            .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.white.opacity(0.1)))
            .contentShape(RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
        .focusable(true)
        .help("Open \(tool.name) official website")
        .accessibilityLabel("Open \(tool.name), best for \(tool.bestFor)")
        .accessibilityHint("Opens the official website in the current Clearframe tab")
    }
}
