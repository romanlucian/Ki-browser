import AppKit
import LimeghostCore
import SwiftUI

struct OnboardingView: View {
    @ObservedObject var controller: OnboardingController
    @ObservedObject var searchSettings: SearchSettingsStore
    let finish: () -> Void

    @FocusState private var primaryActionFocused: Bool
    @State private var keyMonitor: Any?

    // Halo tokens (B7): both constants used to be one-off literals — accent
    // was a hardcoded lime, deepGreen its dark badge backdrop. Sourcing them
    // from LimeghostTheme keeps this intro visually in step with the rest
    // of the redesigned chrome without threading the theme through every
    // call site below (they all already read `accent`/`deepGreen`).
    private let accent = LimeghostTheme.accent
    private let deepGreen = LimeghostTheme.accentDimStrong

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [LimeghostTheme.bg0, LimeghostTheme.bg1],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                topBar
                Group {
                    switch controller.step {
                    case .welcome: welcomeStep
                    case .search: searchStep
                    case .privacy: privacyStep
                    case .assistant: assistantStep
                    case .compare: compareStep
                    case .reader: readerStep
                    case .makeItYours: makeItYoursStep
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
        .accessibilityLabel("Limeghost introduction")
    }

    private var topBar: some View {
        HStack(spacing: 14) {
            HStack(spacing: 10) {
                // The mark itself, not a letter. This drew a serif "C" until
                // September 1, 2026 — the Clearframe initial, left behind by
                // the rename in the one place a new person looks first.
                BrandMark(size: 30)
                    .frame(width: 38, height: 38)
                    .background(deepGreen, in: RoundedRectangle(cornerRadius: 11))
                VStack(alignment: .leading, spacing: 2) {
                    Text("LIMEGHOST")
                        .font(.system(size: 11, weight: .bold))
                        .tracking(1.8)
                        .foregroundStyle(Color.white.opacity(0.76))
                    Text("by Zincoo")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Color.white.opacity(0.42))
                }
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
        VStack(alignment: .leading, spacing: 20) {
            Spacer(minLength: 0)
            Text("The AI world, made simple.")
                .font(.system(size: 46, weight: .bold, design: .serif))
                .foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true)
            Text("Limeghost puts the AI you already use beside the page you are reading, and hands it the article rather than the whole cluttered site. It holds no key of its own and calls no model — everything below happens on this Mac, or in your own account.")
                .font(.system(size: 16))
                .foregroundStyle(Color.white.opacity(0.68))
                .lineSpacing(4)
                .frame(maxWidth: 660, alignment: .leading)

            HStack(spacing: 13) {
                PromiseCard(symbol: "bubble.left.and.text.bubble.right", title: "Ask", detail: "Your own ChatGPT, Claude, Gemini, Le Chat or Grok, beside the page")
                PromiseCard(symbol: "doc.plaintext", title: "Read", detail: "The article without the menus — and it is what your AI gets")
                PromiseCard(symbol: "exclamationmark.shield", title: "Notice", detail: "Explain visible risk signals, never issue verdicts")
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: 850, maxHeight: .infinity, alignment: .leading)
    }

    private var searchStep: some View {
        VStack(alignment: .leading, spacing: 18) {
            Spacer(minLength: 0)
            Text("Choose how you search.")
                .font(.system(size: 40, weight: .bold, design: .serif))
                .foregroundStyle(.white)
            Text("This affects address-bar searches only. Website addresses always open directly, and you can change it later in Settings.")
                .font(.system(size: 15))
                .foregroundStyle(Color.white.opacity(0.62))
                .frame(maxWidth: 620, alignment: .leading)
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
            .frame(maxWidth: 720, alignment: .leading)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: 850, maxHeight: .infinity, alignment: .leading)
    }

    /// Rewritten September 1, 2026. It used to promise that "after you
    /// configure it and deliberately request an online action, the provider
    /// receives the page title, hostname, language, and extracted text" — a
    /// description of a provider layer deleted on August 30. It was the first
    /// privacy claim a new person read, and it was false in the direction that
    /// matters: it implied Limeghost might send a page somewhere.
    private var privacyStep: some View {
        VStack(alignment: .leading, spacing: 18) {
            Spacer(minLength: 0)
            Text("Nothing leaves this Mac by itself.")
                .font(.system(size: 40, weight: .bold, design: .serif))
                .foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true)
            VStack(spacing: 10) {
                PrivacyLine(symbol: "key.slash", title: "Limeghost has no AI key", detail: "It calls no model and pays for no service. There is nothing to configure and nothing to switch off.")
                PrivacyLine(symbol: "doc.on.clipboard", title: "A page moves by your clipboard", detail: "Reading a page happens here. The only way its text reaches an AI is you copying it and pasting it yourself — so you can see exactly what you are handing over, and to whom.")
                PrivacyLine(symbol: "person.crop.circle", title: "The assistant is your own account", detail: "ChatGPT, Claude, Gemini, Le Chat and Grok open as ordinary websites, signed in as you. Limeghost never types into them or reads what they say.")
                PrivacyLine(symbol: "internaldrive", title: "History and bookmarks stay here", detail: "Kept in this Mac user profile, never sold, never included in anything sent anywhere.")
            }
            .frame(maxWidth: 820)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: 850, maxHeight: .infinity, alignment: .leading)
    }

    private var assistantStep: some View {
        FeatureStep(
            title: "Your AI, beside the page.",
            detail: "Press ⇧⌘A and the assistant opens on the right, on your own account. Read on the left, ask on the right, without a second window.",
            shortcut: "⇧⌘A",
            accent: accent
        ) {
            AssistantPreview(accent: accent)
        }
    }

    private var compareStep: some View {
        FeatureStep(
            title: "Two answers, side by side.",
            detail: "Ask the same question twice and read both. Two is the limit on purpose — three would be a vote, and models that share training data share their mistakes.",
            shortcut: nil,
            accent: accent
        ) {
            ComparePreview(accent: accent)
        }
    }

    private var readerStep: some View {
        FeatureStep(
            title: "See what your AI will get.",
            detail: "⇧⌘R shows the article Limeghost pulled out of the page — no menus, no footers, no player controls. It is exactly the text ⇧⌘C puts on your clipboard, so nothing is hidden between reading it and sending it.",
            shortcut: "⇧⌘R",
            accent: accent
        ) {
            ReaderPreview(accent: accent)
        }
    }

    private var makeItYoursStep: some View {
        FeatureStep(
            title: "Make it yours.",
            detail: "Bookmark folders take an icon from \(LimeghostIconCatalog.all.count.formatted()) drawings across three sets, and Limeghost's own set takes your colour. Tracker blocking runs from a curated list — it is not a complete ad blocker, and WebKit never reports what it stopped, so you will never see an invented number.",
            shortcut: nil,
            accent: accent
        ) {
            IconsPreview(accent: accent)
        }
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
            .foregroundStyle(LimeghostTheme.onAccent)
            .focused($primaryActionFocused)
        }
        .frame(maxWidth: 920)
        .padding(.horizontal, 42)
        .frame(height: 68)
    }

    private var primaryActionTitle: String {
        guard controller.step.isLast else { return "Continue" }
        return controller.isInitialPresentation ? "Start browsing" : "Return to browsing"
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
        if controller.step.isLast {
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
                .foregroundStyle(LimeghostTheme.accent)
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
                .foregroundStyle(LimeghostTheme.accent)
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
                .foregroundStyle(LimeghostTheme.onAccent)
                .frame(width: 25, height: 25)
                .background(LimeghostTheme.accent, in: Circle())
            Text(text).font(.system(size: 13, weight: .medium)).foregroundStyle(Color.white.opacity(0.82))
        }
    }
}

/// The shape the four feature steps share: words on the left, the thing itself
/// on the right. They lead with a picture because the founder's note on the old
/// step was that it explained where it could have shown.
private struct FeatureStep<Preview: View>: View {
    let title: String
    let detail: String
    let shortcut: String?
    let accent: Color
    @ViewBuilder var preview: () -> Preview

    var body: some View {
        HStack(spacing: 34) {
            VStack(alignment: .leading, spacing: 17) {
                Text(title)
                    .font(.system(size: 38, weight: .bold, design: .serif))
                    .foregroundStyle(.white)
                    .fixedSize(horizontal: false, vertical: true)
                Text(detail)
                    .font(.system(size: 15))
                    .foregroundStyle(Color.white.opacity(0.64))
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
                if let shortcut {
                    HStack(spacing: 9) {
                        Text(shortcut)
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                            .foregroundStyle(LimeghostTheme.onAccent)
                            .padding(.horizontal, 11)
                            .padding(.vertical, 6)
                            .background(accent, in: RoundedRectangle(cornerRadius: 8))
                        Text("also in the Page menu")
                            .font(.caption)
                            .foregroundStyle(Color.white.opacity(0.42))
                    }
                }
            }
            .frame(maxWidth: 420, alignment: .leading)

            preview()
                .frame(maxWidth: 380)
        }
        .frame(maxWidth: 850, maxHeight: .infinity)
    }
}

/// A window with the assistant docked on its right, drawn rather than
/// screenshotted so it cannot go stale the way this tour just did.
private struct AssistantPreview: View {
    let accent: Color

    var body: some View {
        PreviewWindow {
            HStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 7) {
                    PreviewLine(width: 0.8)
                    PreviewLine(width: 1.0)
                    PreviewLine(width: 0.9)
                    PreviewLine(width: 0.55)
                }
                .padding(13)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

                Rectangle().fill(Color.white.opacity(0.09)).frame(width: 1)

                VStack(spacing: 9) {
                    HStack(spacing: 6) {
                        Circle().fill(accent).frame(width: 13, height: 13)
                        Text("your AI")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(Color.white.opacity(0.72))
                        Spacer()
                    }
                    RoundedRectangle(cornerRadius: 7)
                        .fill(Color.white.opacity(0.07))
                        .frame(height: 44)
                    RoundedRectangle(cornerRadius: 7)
                        .fill(accent.opacity(0.16))
                        .frame(height: 30)
                    Spacer()
                }
                .padding(11)
                .frame(width: 132)
            }
        }
    }
}

/// Two assistants filling the window, which is what Compare actually does.
private struct ComparePreview: View {
    let accent: Color

    var body: some View {
        PreviewWindow {
            HStack(spacing: 0) {
                comparePane(label: "one", tint: accent)
                Rectangle().fill(Color.white.opacity(0.09)).frame(width: 1)
                comparePane(label: "two", tint: Color.white.opacity(0.5))
            }
        }
    }

    private func comparePane(label: String, tint: Color) -> some View {
        VStack(spacing: 8) {
            HStack(spacing: 6) {
                Circle().fill(tint).frame(width: 11, height: 11)
                Text(label)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.66))
                Spacer()
            }
            PreviewLine(width: 1.0)
            PreviewLine(width: 0.85)
            PreviewLine(width: 0.95)
            PreviewLine(width: 0.6)
            Spacer()
        }
        .padding(11)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

/// One column of clean prose with a word count — Reader's own header, in
/// miniature.
private struct ReaderPreview: View {
    let accent: Color

    var body: some View {
        PreviewWindow {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 7) {
                    Image(systemName: "doc.plaintext")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(accent)
                    Text("Reader")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.white)
                    Spacer()
                    Text("871 words · 4 min")
                        .font(.system(size: 9))
                        .foregroundStyle(Color.white.opacity(0.4))
                }
                Rectangle().fill(Color.white.opacity(0.09)).frame(height: 1)
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color.white.opacity(0.5))
                    .frame(width: 150, height: 11)
                VStack(alignment: .leading, spacing: 6) {
                    PreviewLine(width: 1.0)
                    PreviewLine(width: 0.94)
                    PreviewLine(width: 0.98)
                    PreviewLine(width: 0.5)
                }
                Spacer()
            }
            .padding(13)
        }
    }
}

/// Real icons from the real catalog, so this cannot drift from what the picker
/// offers. Limeghost's own set is the tintable one, which is why these take the
/// accent.
private struct IconsPreview: View {
    let accent: Color

    private var sample: [LimeghostIcon] {
        Array(LimeghostIconCatalog.all.filter { $0.style == .limeghost }.prefix(18))
    }

    var body: some View {
        PreviewWindow {
            VStack(alignment: .leading, spacing: 11) {
                HStack(spacing: 7) {
                    Image(systemName: "folder")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(accent)
                    Text("Folder icon")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.white)
                    Spacer()
                    Text("\(LimeghostIconCatalog.all.count.formatted()) to choose from")
                        .font(.system(size: 9))
                        .foregroundStyle(Color.white.opacity(0.4))
                }
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 6), spacing: 9) {
                    ForEach(sample) { icon in
                        LimeghostIconView(iconID: icon.id, size: 20)
                            .foregroundStyle(accent)
                    }
                }
                Spacer()
            }
            .padding(13)
        }
    }
}

/// The frame the four previews share — traffic lights and a rounded body, so a
/// drawing reads as a window rather than as decoration.
private struct PreviewWindow<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 5) {
                Circle().fill(Color(red: 1, green: 0.37, blue: 0.34)).frame(width: 8, height: 8)
                Circle().fill(Color(red: 1, green: 0.74, blue: 0.18)).frame(width: 8, height: 8)
                Circle().fill(Color(red: 0.16, green: 0.79, blue: 0.25)).frame(width: 8, height: 8)
                Spacer()
            }
            .padding(.horizontal, 11)
            .frame(height: 26)
            content()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(height: 236)
        .background(LimeghostTheme.bg1, in: RoundedRectangle(cornerRadius: 13))
        .overlay(RoundedRectangle(cornerRadius: 13).stroke(Color.white.opacity(0.09)))
    }
}

/// A line of text that is not text, for the drawn windows above.
private struct PreviewLine: View {
    let width: CGFloat

    var body: some View {
        GeometryReader { geometry in
            RoundedRectangle(cornerRadius: 2)
                .fill(Color.white.opacity(0.17))
                .frame(width: geometry.size.width * width, height: 6)
        }
        .frame(height: 6)
    }
}
