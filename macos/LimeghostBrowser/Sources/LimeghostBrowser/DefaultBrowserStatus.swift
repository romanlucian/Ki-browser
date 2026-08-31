import AppKit
import SwiftUI

/// Whether this Mac opens links in Limeghost, and the one action that changes
/// it.
///
/// A browser nobody can make their default is a browser nobody uses for
/// anything real: every link from Mail, Messages, Slack, or a document keeps
/// opening somewhere else, and the browser becomes a place you visit rather
/// than the one you live in. Limeghost already declares `http` and `https` in
/// its bundle, so it has always been eligible — it simply never asked.
///
/// macOS owns the decision. `setDefaultApplication` shows the system's own
/// confirmation, and the answer is the system's to give; this type only asks
/// and then reports what the system says afterwards, rather than assuming the
/// request was granted.
@MainActor
final class DefaultBrowserStatus: ObservableObject {
    enum State: Equatable {
        case isDefault
        /// Another browser holds it. The name is for telling the reader which.
        case notDefault(current: String?)
        /// macOS would not say — an unsigned build, or no handler registered.
        case unknown
    }

    @Published private(set) var state: State = .unknown
    /// Set when a request was made and the system did not grant it, so the
    /// interface can say so instead of silently doing nothing.
    @Published private(set) var lastRequestFailed = false

    init() {
        refresh()
    }

    func refresh() {
        guard let probe = URL(string: "https://example.com") else {
            state = .unknown
            return
        }
        guard let handler = NSWorkspace.shared.urlForApplication(toOpen: probe) else {
            state = .unknown
            return
        }
        if handler.standardizedFileURL == Bundle.main.bundleURL.standardizedFileURL {
            state = .isDefault
            lastRequestFailed = false
        } else {
            state = .notDefault(current: FileManager.default.displayName(atPath: handler.path))
        }
    }

    /// Asks macOS to route web links here. The system decides, and asks the
    /// reader itself; there is no way — and no reason to want one — to make
    /// this change without them seeing it.
    func makeDefault() {
        lastRequestFailed = false
        let bundle = Bundle.main.bundleURL
        var remaining = 2

        for scheme in ["http", "https"] {
            NSWorkspace.shared.setDefaultApplication(at: bundle, toOpenURLsWithScheme: scheme) { [weak self] error in
                Task { @MainActor in
                    guard let self else { return }
                    if error != nil { self.lastRequestFailed = true }
                    remaining -= 1
                    if remaining == 0 {
                        // Launch Services settles a moment after it answers.
                        try? await Task.sleep(nanoseconds: 400_000_000)
                        self.refresh()
                    }
                }
            }
        }
    }
}

/// The Settings row: where links currently open, and a way to change it.
struct DefaultBrowserSettingsSection: View {
    @StateObject private var status = DefaultBrowserStatus()

    var body: some View {
        Section("Default browser") {
            switch status.state {
            case .isDefault:
                Label("Links on this Mac open in Limeghost", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(LimeghostTheme.accent)
            case .notDefault(let current):
                HStack {
                    Text(current.map { "Links open in \($0)" } ?? "Links open in another browser")
                    Spacer()
                    Button("Make Limeghost the default") { status.makeDefault() }
                }
            case .unknown:
                HStack {
                    Text("macOS did not report which browser opens links")
                    Spacer()
                    Button("Try to set Limeghost") { status.makeDefault() }
                }
            }

            if status.lastRequestFailed {
                Text("macOS declined the change. A build that is not Developer ID signed can be refused; you can also set it in System Settings → Desktop & Dock → Default web browser.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("Limeghost asks macOS, and macOS asks you. Nothing changes without your confirmation, and you can change it back in System Settings → Desktop & Dock at any time.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .onAppear { status.refresh() }
    }
}
