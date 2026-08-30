import AppKit
import ClearframeCore
import SwiftUI

struct AssistantPanel: View {
    @ObservedObject var model: PageAssistantModel
    @ObservedObject var session: BrowserSession
    @State private var showsPreview = false
    @State private var didCopy = false

    var body: some View {
        ZStack {
            Color(nsColor: .controlBackgroundColor)
            switch model.state {
            case .idle:
                emptyState
            case .loading(let message):
                loadingState(message)
            case .structureNotice:
                structureNoticeState
            case .needsPage:
                needsPageState
            case .failed(let message):
                errorState(message)
            case .ready:
                if let snapshot = model.snapshot, let analysis = model.analysis {
                    results(snapshot: snapshot, analysis: analysis)
                } else {
                    emptyState
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 18) {
            Spacer()
            ZStack {
                Circle().stroke(Color.primary.opacity(0.14), lineWidth: 1).frame(width: 92, height: 92)
                RoundedRectangle(cornerRadius: 22)
                    .fill(ClearframeTheme.accentDimStrong)
                    .frame(width: 64, height: 64)
                Text("C")
                    .font(.system(size: 32, weight: .bold, design: .serif))
                    .foregroundStyle(ClearframeTheme.accent)
            }
            Text("PAGE INTELLIGENCE")
                .font(.system(size: 10, weight: .bold))
                .tracking(1.4)
                .foregroundStyle(ClearframeTheme.accent)
            Text("Understand this page")
                .font(.system(size: 27, weight: .bold, design: .serif))
            Text("Check a page for visible risk signals, and get its readable text ready for the AI you use.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineSpacing(4)
                .frame(maxWidth: 300)
            Button {
                Task { await model.analyzeCurrentPage(session: session) }
            } label: {
                Label("Analyze page", systemImage: "sparkles")
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
            }
            .buttonStyle(.borderedProminent)
            .tint(ClearframeTheme.accent)
            .foregroundStyle(ClearframeTheme.onAccent)
            .frame(maxWidth: 300)
            Text("Local by default · runs only when you click")
                .font(.caption2)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(28)
    }

    private func loadingState(_ message: String) -> some View {
        VStack(spacing: 14) {
            ProgressView()
                .controlSize(.large)
            Text(message)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private var structureNoticeState: some View {
        VStack(spacing: 16) {
            Image(systemName: "rectangle.stack")
                .font(.system(size: 36))
                .foregroundStyle(ClearframeTheme.accent)
            Text("This looks like a section page")
                .font(.title3.bold())
            Text("It lists many different articles rather than one text to summarize. Open one of its articles for a grounded analysis.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Analyze anyway") {
                Task { await model.analyzeDespiteStructure(session: session) }
            }
            .buttonStyle(.borderedProminent)
            .tint(ClearframeTheme.accent)
            .foregroundStyle(ClearframeTheme.onAccent)
        }
        .padding(28)
    }

    /// Analyze page pressed on a tab that holds no web page. A calm refusal,
    /// not an error: nothing went wrong, there is simply nothing to read yet.
    private var needsPageState: some View {
        VStack(spacing: 16) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 36))
                .foregroundStyle(ClearframeTheme.accent)
            Text("No page to analyze yet")
                .font(.title3.bold())
            Text(PageAssistantModel.needsPageMessage)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Analyze page") {
                Task { await model.analyzeCurrentPage(session: session) }
            }
            .buttonStyle(.borderedProminent)
            .tint(ClearframeTheme.accent)
            .foregroundStyle(ClearframeTheme.onAccent)
        }
        .padding(28)
    }

    private func errorState(_ message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.circle")
                .font(.system(size: 36))
                .foregroundStyle(.orange)
            Text("Couldn’t analyze this page")
                .font(.title3.bold())
            Text(message)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Try local analysis again") {
                Task { await model.analyzeCurrentPage(session: session) }
            }
            .buttonStyle(.borderedProminent)
            .tint(ClearframeTheme.accent)
            .foregroundStyle(ClearframeTheme.onAccent)
        }
        .padding(28)
    }

    private func results(snapshot: PageSnapshot, analysis: PageAnalysis) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                if let message = model.operationMessage {
                    HStack(spacing: 9) {
                        ProgressView().controlSize(.small)
                        Text(message)
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.blue.opacity(0.08), in: RoundedRectangle(cornerRadius: 9))
                }

                if let message = model.operationError {
                    Label(message, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.orange.opacity(0.09), in: RoundedRectangle(cornerRadius: 9))
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text(snapshot.hostname.uppercased())
                        .font(.system(size: 10, weight: .bold))
                        .tracking(1.2)
                        .foregroundStyle(ClearframeTheme.accent)
                    Text(snapshot.title)
                        .font(.system(size: 22, weight: .bold, design: .serif))
                        .lineLimit(3)
                    Text("\(analysis.readingTimeMinutes) min read · \(snapshot.language.isEmpty ? "language not declared" : snapshot.language)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.bottom, 4)

                RiskCard(assessment: analysis.risk)

                assistantCard {
                    HStack {
                        sectionLabel("COPY FOR AI")
                        Spacer()
                        Text("\(model.readableText.count) CHARACTERS")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.secondary)
                    }
                    Text("Clearframe pulled \(LocalAnalysisEngine.wordCount(of: model.readableText)) words of readable text off this page, without the menus, footers and player controls.")
                        .font(.callout)
                        .lineSpacing(3)

                    Button(showsPreview ? "Hide what will be copied" : "See exactly what will be copied") {
                        showsPreview.toggle()
                    }
                    .buttonStyle(.link)
                    .font(.caption)

                    if showsPreview {
                        ScrollView {
                            Text(model.readableText)
                                .font(.system(size: 11))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(9)
                        }
                        .frame(maxHeight: 260)
                        .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 9))
                        .overlay(RoundedRectangle(cornerRadius: 9).stroke(Color.primary.opacity(0.08)))
                    }

                    Button {
                        copyForAI(snapshot: snapshot)
                    } label: {
                        Label(didCopy ? "Copied — paste it into your AI" : "Copy page for AI", systemImage: didCopy ? "checkmark" : "doc.on.doc")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(ClearframeTheme.accent)
                    .disabled(model.readableText.isEmpty)

                    Text("Nothing is sent anywhere by Clearframe. Copying puts this text on the Mac's clipboard, which other apps — and Universal Clipboard, if it is on — can read.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineSpacing(2)
                }

                Text("Clearframe does not summarise this page or judge what matters in it. Risk signals are visible-page heuristics, not a security verdict.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineSpacing(3)
                    .padding(10)
            }
            .padding(14)
        }
    }

    /// Puts the readable text on the clipboard, headed by where it came from, so the
    /// person pasting it — and whatever reads it afterwards — can see the source.
    private func copyForAI(snapshot: PageSnapshot) {
        let words = LocalAnalysisEngine.wordCount(of: model.readableText)
        let payload = """
        Title:  \(snapshot.title)
        URL:    \(snapshot.url)
        \(words) words extracted from the visible page

        \(model.readableText)
        """
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(payload, forType: .string)
        didCopy = true
    }

    private func assistantCard<Content: View>(
        accent: Color = .clear,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 11, content: content)
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(nsColor: .windowBackgroundColor), in: RoundedRectangle(cornerRadius: 13))
            .overlay(alignment: .leading) {
                if accent != .clear {
                    Rectangle().fill(accent).frame(width: 3).clipShape(Capsule()).padding(.vertical, 10)
                }
            }
            .overlay(RoundedRectangle(cornerRadius: 13).stroke(Color.primary.opacity(0.07)))
    }

    private func sectionLabel(_ value: String) -> some View {
        Text(value)
            .font(.system(size: 10, weight: .bold))
            .tracking(1.1)
            .foregroundStyle(ClearframeTheme.accent)
    }
}

private struct RiskCard: View {
    let assessment: RiskAssessment

    private var tint: Color {
        switch assessment.level {
        case .low: return .green
        case .caution: return .orange
        case .high: return .red
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Circle().fill(tint).frame(width: 8, height: 8)
                Text("\(assessment.level.rawValue) risk signals").font(.callout.bold())
                Spacer()
                Text("\(assessment.score) / 100").font(.caption2).foregroundStyle(.secondary)
            }
            Text(
                assessment.signals.isEmpty
                    ? "No obvious high-risk signals were found in the visible page. That does not prove it is safe."
                    : "\(assessment.signals.count) visible signal\(assessment.signals.count == 1 ? "" : "s") worth checking. This is not a verdict."
            )
            .font(.caption)
            .foregroundStyle(.secondary)
            ForEach(assessment.signals) { signal in
                DisclosureGroup(signal.title) {
                    Text(signal.detail).font(.caption).foregroundStyle(.secondary).padding(.top, 4)
                }
                .font(.caption.bold())
            }
        }
        .padding(14)
        .background(tint.opacity(0.09), in: RoundedRectangle(cornerRadius: 13))
        .overlay(RoundedRectangle(cornerRadius: 13).stroke(tint.opacity(0.24)))
    }
}
