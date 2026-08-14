import AppKit
import ClearframeCore
import SwiftUI

struct OnboardingView: View {
    @ObservedObject var controller: OnboardingController
    @ObservedObject var searchSettings: SearchSettingsStore
    let finish: () -> Void

    @FocusState private var primaryActionFocused: Bool
    @State private var keyMonitor: Any?

    private let accent = Color(red: 0.79, green: 0.94, blue: 0.39)
    private let deepGreen = Color(red: 0.035, green: 0.20, blue: 0.145)

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.025, green: 0.105, blue: 0.075),
                    Color(red: 0.045, green: 0.07, blue: 0.06),
                    Color(nsColor: .windowBackgroundColor)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                topBar
                Group {
                    switch controller.step {
                    case .welcome: welcomeStep
                    case .searchAndPrivacy: searchAndPrivacyStep
                    case .analyzePages: analyzeStep
                    }
                }
                .frame(maxWidth: 920, maxHeight: .infinity)
                .padding(.horizontal, 42)
                actionBar
            }
            .padding(.vertical, 24)
        }
        .transition(.opacity)
        .onAppear {
            focusPrimaryAction()
            installKeyMonitor()
        }
        .onDisappear { removeKeyMonitor() }
        .onChange(of: controller.step) { _, _ in focusPrimaryAction() }
        .accessibilityLabel("Clearframe introduction")
    }

    private var topBar: some View {
        HStack(spacing: 14) {
            HStack(spacing: 10) {
                Text("C")
                    .font(.system(size: 20, weight: .bold, design: .serif))
                    .foregroundStyle(accent)
                    .frame(width: 38, height: 38)
                    .background(deepGreen, in: RoundedRectangle(cornerRadius: 11))
                Text("CLEARFRAME")
                    .font(.system(size: 11, weight: .bold))
                    .tracking(1.8)
                    .foregroundStyle(Color.white.opacity(0.76))
            }

            Spacer()
            HStack(spacing: 7) {
                ForEach(OnboardingStep.allCases, id: \.rawValue) { step in
                    Capsule()
                        .fill(step == controller.step ? accent : Color.white.opacity(0.14))
                        .frame(width: step == controller.step ? 28 : 8, height: 8)
                        .animation(.easeInOut(duration: 0.2), value: controller.step)
                }
            }
            .accessibilityLabel("Step \(controller.step.rawValue + 1) of \(OnboardingStep.allCases.count)")

            Spacer()
            Button("Skip introduction", action: finish)
                .buttonStyle(.plain)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.62))
        }
        .padding(.horizontal, 32)
        .frame(height: 48)
    }

    private var welcomeStep: some View {
        VStack(spacing: 30) {
            Spacer(minLength: 18)
            VStack(spacing: 15) {
                Text("Browse with a clearer frame.")
                    .font(.system(size: 49, weight: .bold, design: .serif))
                    .tracking(-1.3)
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                Text("Clearframe helps you understand unfamiliar pages, compare sources, and notice obvious pressure or risk signals—without turning every page into a chat session.")
                    .font(.system(size: 16))
                    .foregroundStyle(Color.white.opacity(0.68))
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
                    .frame(maxWidth: 680)
            }

            HStack(spacing: 14) {
                PromiseCard(symbol: "doc.text.magnifyingglass", title: "Understand", detail: "Local summaries and claims worth checking")
                PromiseCard(symbol: "rectangle.2.swap", title: "Compare", detail: "Put two sources side by side without fake certainty")
                PromiseCard(symbol: "exclamationmark.shield", title: "Notice", detail: "Explain visible risk signals, never issue verdicts")
            }
            .frame(maxWidth: 820)
            Spacer(minLength: 18)
        }
    }

    private var searchAndPrivacyStep: some View {
        VStack(spacing: 25) {
            Spacer(minLength: 12)
            VStack(spacing: 10) {
                Text("Choose how you search.")
                    .font(.system(size: 40, weight: .bold, design: .serif))
                    .foregroundStyle(.white)
                Text("This choice affects address-bar searches only. Website addresses always open directly.")
                    .font(.system(size: 15))
                    .foregroundStyle(Color.white.opacity(0.64))
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 142, maximum: 175), spacing: 10)], spacing: 10) {
                ForEach(SearchEngine.allCases) { engine in
                    SearchProviderCard(
                        engine: engine,
                        selected: searchSettings.selectedEngine == engine,
                        select: { searchSettings.selectedEngine = engine },
                        accent: accent
                    )
                }
            }
            .frame(maxWidth: 820)

            VStack(spacing: 10) {
                PrivacyLine(symbol: "square.grid.2x2", title: "The AI guide is local", detail: "Its curated cards and filters are bundled in Clearframe; opening one is ordinary website navigation.")
                PrivacyLine(symbol: "lock.shield", title: "Analyze is local by default", detail: "Visible page text is extracted only after you click Analyze page. It is not sold or passively uploaded.")
                PrivacyLine(symbol: "cloud", title: "Online AI is optional", detail: "After you configure it and deliberately request an online action, the provider receives the page title, hostname, language, and extracted text—not the full URL, cookies, forms, or history.")
            }
            .frame(maxWidth: 820)
            Spacer(minLength: 12)
        }
    }

    private var analyzeStep: some View {
        HStack(spacing: 34) {
            VStack(alignment: .leading, spacing: 19) {
                Text("The useful part is one click away.")
                    .font(.system(size: 40, weight: .bold, design: .serif))
                    .foregroundStyle(.white)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Open an article, guide, product page, or unfamiliar site. Then open Assistant and choose Analyze page.")
                    .font(.system(size: 15))
                    .foregroundStyle(Color.white.opacity(0.66))
                    .lineSpacing(3)

                VStack(alignment: .leading, spacing: 13) {
                    OnboardingInstruction(number: "1", text: "Open a page you want to understand")
                    OnboardingInstruction(number: "2", text: "Click Assistant, then Analyze page")
                    OnboardingInstruction(number: "3", text: "Review the summary, claims, and explained signals")
                }

                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "sparkles")
                        .foregroundStyle(accent)
                    Text("Clearframe Pro may arrive later for heavier online AI use. There is no purchase or paywall in this introduction, and local browsing tools remain the foundation.")
                        .font(.caption)
                        .foregroundStyle(Color.white.opacity(0.53))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(14)
                .background(Color.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 12))
            }
            .frame(maxWidth: 430, alignment: .leading)

            AnalyzePreview(accent: accent)
                .frame(maxWidth: 360)
        }
        .frame(maxWidth: 850, maxHeight: .infinity)
    }

    private var actionBar: some View {
        HStack {
            if controller.step != .welcome {
                Button("Back") { controller.goBack() }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .tint(.white.opacity(0.5))
            }
            Spacer()
            Button(primaryActionTitle) {
                performPrimaryAction()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .tint(accent)
            .foregroundStyle(Color(red: 0.04, green: 0.12, blue: 0.085))
            .focused($primaryActionFocused)
        }
        .frame(maxWidth: 920)
        .padding(.horizontal, 42)
        .frame(height: 68)
    }

    private var primaryActionTitle: String {
        switch controller.step {
        case .welcome: return "Continue"
        case .searchAndPrivacy: return "Continue"
        case .analyzePages: return controller.isInitialPresentation ? "Start browsing" : "Return to browsing"
        }
    }

    private func focusPrimaryAction() {
        Task { @MainActor in
            NSApp.keyWindow?.makeFirstResponder(nil)
            await Task.yield()
            primaryActionFocused = true
            try? await Task.sleep(nanoseconds: 180_000_000)
            guard controller.isPresented else { return }
            primaryActionFocused = true
        }
    }

    private func performPrimaryAction() {
        if controller.step == .analyzePages {
            finish()
        } else {
            controller.advance()
        }
    }

    private func installKeyMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard controller.isPresented else { return event }
            switch event.keyCode {
            case 36, 76:
                Task { @MainActor in performPrimaryAction() }
                return nil
            case 53:
                Task { @MainActor in finish() }
                return nil
            default:
                return event
            }
        }
    }

    private func removeKeyMonitor() {
        guard let keyMonitor else { return }
        NSEvent.removeMonitor(keyMonitor)
        self.keyMonitor = nil
    }
}

private struct PromiseCard: View {
    let symbol: String
    let title: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            Image(systemName: symbol)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Color(red: 0.79, green: 0.94, blue: 0.39))
            Text(title).font(.headline).foregroundStyle(.white)
            Text(detail)
                .font(.caption)
                .foregroundStyle(Color.white.opacity(0.56))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(18)
        .frame(maxWidth: .infinity, minHeight: 132, alignment: .topLeading)
        .background(Color.white.opacity(0.065), in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.white.opacity(0.09)))
    }
}

private struct SearchProviderCard: View {
    let engine: SearchEngine
    let selected: Bool
    let select: () -> Void
    let accent: Color

    var body: some View {
        Button(action: select) {
            VStack(alignment: .leading, spacing: 13) {
                HStack {
                    Text(engine.displayName.prefix(2).uppercased())
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .frame(width: 34, height: 34)
                        .background(selected ? accent : Color.white.opacity(0.11), in: RoundedRectangle(cornerRadius: 10))
                        .foregroundStyle(selected ? Color.black.opacity(0.7) : Color.white.opacity(0.8))
                    Spacer()
                    Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(selected ? accent : Color.white.opacity(0.22))
                }
                Text(engine.displayName)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: 92, alignment: .leading)
            .background(Color.white.opacity(selected ? 0.095 : 0.05), in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(selected ? accent.opacity(0.8) : Color.white.opacity(0.08), lineWidth: selected ? 1.5 : 1))
        }
        .buttonStyle(.plain)
        .focusable(true)
        .accessibilityLabel("Use \(engine.displayName) for address-bar searches")
        .accessibilityValue(selected ? "Selected" : "Not selected")
    }
}

private struct PrivacyLine: View {
    let symbol: String
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 13) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color(red: 0.79, green: 0.94, blue: 0.39))
                .frame(width: 30, height: 30)
                .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 9))
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 13, weight: .semibold)).foregroundStyle(.white)
                Text(detail).font(.caption).foregroundStyle(Color.white.opacity(0.56)).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(Color.black.opacity(0.13), in: RoundedRectangle(cornerRadius: 12))
    }
}

private struct OnboardingInstruction: View {
    let number: String
    let text: String

    var body: some View {
        HStack(spacing: 11) {
            Text(number)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Color(red: 0.04, green: 0.12, blue: 0.085))
                .frame(width: 25, height: 25)
                .background(Color(red: 0.79, green: 0.94, blue: 0.39), in: Circle())
            Text(text).font(.system(size: 13, weight: .medium)).foregroundStyle(Color.white.opacity(0.82))
        }
    }
}

private struct AnalyzePreview: View {
    let accent: Color

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Circle().fill(Color.red.opacity(0.75)).frame(width: 8, height: 8)
                Circle().fill(Color.yellow.opacity(0.75)).frame(width: 8, height: 8)
                Circle().fill(Color.green.opacity(0.75)).frame(width: 8, height: 8)
                Spacer()
                Text("Assistant")
                    .font(.system(size: 10, weight: .semibold))
                    .padding(.horizontal, 9)
                    .frame(height: 25)
                    .background(Color(red: 0.06, green: 0.36, blue: 0.27), in: RoundedRectangle(cornerRadius: 8))
            }
            .padding(12)
            .background(Color.black.opacity(0.28))

            VStack(spacing: 17) {
                Text("C")
                    .font(.system(size: 28, weight: .bold, design: .serif))
                    .foregroundStyle(accent)
                    .frame(width: 56, height: 56)
                    .background(Color(red: 0.05, green: 0.30, blue: 0.22), in: RoundedRectangle(cornerRadius: 17))
                Text("Understand this page")
                    .font(.system(size: 23, weight: .bold, design: .serif))
                    .foregroundStyle(.white)
                Text("Create a local summary, surface claims worth checking, and notice obvious visible risk signals.")
                    .font(.caption)
                    .foregroundStyle(Color.white.opacity(0.58))
                    .multilineTextAlignment(.center)
                Label("Analyze page", systemImage: "sparkles")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 42)
                    .background(Color(red: 0.06, green: 0.38, blue: 0.28), in: RoundedRectangle(cornerRadius: 9))
                Text("Local by default · runs only when you click")
                    .font(.system(size: 10))
                    .foregroundStyle(Color.white.opacity(0.4))
            }
            .padding(26)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(height: 390)
        .background(Color(red: 0.075, green: 0.09, blue: 0.08), in: RoundedRectangle(cornerRadius: 19))
        .clipShape(RoundedRectangle(cornerRadius: 19))
        .overlay(RoundedRectangle(cornerRadius: 19).stroke(Color.white.opacity(0.1)))
        .shadow(color: .black.opacity(0.28), radius: 30, y: 16)
    }
}
