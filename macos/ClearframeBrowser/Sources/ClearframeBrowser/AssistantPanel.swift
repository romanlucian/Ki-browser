import ClearframeCore
import SwiftUI

struct AssistantPanel: View {
    @ObservedObject var model: PageAssistantModel
    @ObservedObject var session: BrowserSession
    @EnvironmentObject private var aiConfiguration: AIConfigurationStore
    @Environment(\.openSettings) private var openSettings
    @State private var translationLanguage = "Plain English"

    private let translationLanguages = [
        "Plain English", "Spanish", "French", "German", "Romanian", "Portuguese", "Japanese"
    ]

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
            Text("Create a local summary, surface claims worth checking, and notice obvious visible risk signals.")
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
                        sectionLabel("THE GIST")
                        Spacer()
                        Text(analysis.mode == .local ? "LOCAL · EXTRACTIVE" : "OPTIONAL AI")
                            .font(.system(size: 9, weight: .bold))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 4)
                            .background(Color.green.opacity(0.14), in: Capsule())
                    }
                    Text(analysis.content.summary)
                        .font(.callout)
                        .lineSpacing(4)
                        .textSelection(.enabled)
                    Text(analysis.mode == .local
                         ? "Private structured extraction · keeps the page language"
                         : "Provider-assisted result · check important points against the page")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Button {
                        guard let configuration = aiConfiguration.providerConfiguration else {
                            openSettings()
                            return
                        }
                        Task { await model.improveWithAI(configuration: configuration) }
                    } label: {
                        Label(
                            aiConfiguration.canUseRemoteAI ? "Improve with AI" : "Configure Optional AI",
                            systemImage: "sparkles"
                        )
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .disabled(model.operationMessage != nil)
                }

                if !analysis.content.keyPoints.isEmpty {
                    assistantCard {
                        sectionLabel("KEY POINTS")
                        ForEach(Array(analysis.content.keyPoints.enumerated()), id: \.offset) { _, point in
                            VStack(alignment: .leading, spacing: 7) {
                                Label {
                                    Text(point).font(.callout).lineSpacing(3)
                                } icon: {
                                    Image(systemName: "arrow.turn.down.right").foregroundStyle(.green)
                                }
                                if analysis.mode == .local {
                                    Button {
                                        Task { await model.revealEvidence(for: point, session: session) }
                                    } label: {
                                        Label("View evidence", systemImage: "text.magnifyingglass")
                                    }
                                    .buttonStyle(.borderless)
                                    .font(.caption.weight(.semibold))
                                    .disabled(model.operationMessage != nil)
                                    if model.revealedEvidence == point {
                                        Text(point)
                                            .font(.caption)
                                            .lineSpacing(3)
                                            .padding(8)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                            .background(Color.green.opacity(0.10), in: RoundedRectangle(cornerRadius: 7))
                                        // A miss has several causes — the page moved on,
                                        // the text sits in an element the highlighter
                                        // cannot reach — and Clearframe does not know
                                        // which. Say what happened, not why.
                                        Text(model.evidenceWasFoundOnPage
                                             ? "Highlighted in the page. This is extracted page text, not an AI citation."
                                             : "This is extracted page text. Clearframe could not locate it in the live page.")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                            Divider()
                        }
                    }
                }

                if !analysis.content.claimsToCheck.isEmpty {
                    assistantCard(accent: .orange) {
                        sectionLabel("CLAIMS TO CHECK")
                        ForEach(Array(analysis.content.claimsToCheck.enumerated()), id: \.offset) { _, claim in
                            Label {
                                Text(claim).font(.callout).lineSpacing(3)
                            } icon: {
                                Image(systemName: "questionmark.circle.fill").foregroundStyle(.orange)
                            }
                        }
                        Text("These are claims from the page, not Clearframe’s conclusions.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }

                assistantCard {
                    sectionLabel("TRANSLATE")
                    Picker("Language", selection: $translationLanguage) {
                        ForEach(translationLanguages, id: \.self) { Text($0).tag($0) }
                    }
                    .labelsHidden()
                    .frame(maxWidth: .infinity)
                    Button("Translate summary") {
                        let canSimplifyLocally = translationLanguage == "Plain English" &&
                            LocalAnalysisEngine.canSimplifyToPlainEnglish(sourceLanguage: snapshot.language)
                        if !canSimplifyLocally && !aiConfiguration.canUseRemoteAI {
                            openSettings()
                        } else {
                            Task {
                                await model.translateSummary(
                                    targetLanguage: translationLanguage,
                                    configuration: aiConfiguration.providerConfiguration
                                )
                            }
                        }
                    }
                    .buttonStyle(.bordered)
                    .disabled(model.operationMessage != nil)
                    if let translated = model.translatedSummary {
                        Text(translated)
                            .font(.callout)
                            .lineSpacing(4)
                            .padding(10)
                            .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
                            .textSelection(.enabled)
                    }
                }


                Text("Summaries can miss context. AI can be wrong. Risk signals are not a security verdict.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineSpacing(3)
                    .padding(10)
            }
            .padding(14)
        }
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
