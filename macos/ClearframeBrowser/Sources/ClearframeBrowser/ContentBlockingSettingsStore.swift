import ClearframeCore
import Combine
import Foundation

/// Local preferences for tracker blocking: one global switch plus the sites the
/// person chose to turn it off for. Exceptions are stored as normalized hosts so
/// `example.com` and `www.example.com` are the same site, and they are cleared
/// together with the rest of the local browsing data.
@MainActor
final class ContentBlockingSettingsStore: ObservableObject {
    @Published private(set) var isEnabled: Bool
    @Published private(set) var disabledHosts: [String]

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        isEnabled = defaults.object(forKey: Keys.enabled) as? Bool ?? true
        disabledHosts = Self.normalized(defaults.stringArray(forKey: Keys.disabledHosts) ?? [])
    }

    func setEnabled(_ value: Bool) {
        guard value != isEnabled else { return }
        isEnabled = value
        defaults.set(value, forKey: Keys.enabled)
    }

    func isDisabled(forHost host: String) -> Bool {
        guard let normalized = Self.normalizedHost(fromHost: host) else { return false }
        return disabledHosts.contains(normalized)
    }

    /// Returns `true` when the stored exceptions changed, so callers only
    /// recompile the rule list when they have to.
    @discardableResult
    func setDisabled(_ disabled: Bool, forHost host: String) -> Bool {
        guard let normalized = Self.normalizedHost(fromHost: host) else { return false }
        var updated = disabledHosts
        if disabled {
            guard !updated.contains(normalized) else { return false }
            updated.append(normalized)
        } else {
            guard updated.contains(normalized) else { return false }
            updated.removeAll { $0 == normalized }
        }
        store(updated)
        return true
    }

    @discardableResult
    func clearExceptions() -> Bool {
        guard !disabledHosts.isEmpty else { return false }
        store([])
        return true
    }

    /// Accepts either a full web URL or a bare host and returns the comparable
    /// form used for exceptions. Non-web input is rejected by the same policy
    /// that guards navigation, history, and bookmarks.
    static func normalizedHost(from value: String) -> String? {
        guard let url = WebURLPolicy.validatedURL(value) else { return nil }
        return normalizedHost(fromHost: url.host ?? "")
    }

    private static func normalizedHost(fromHost value: String) -> String? {
        let host = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !host.isEmpty, !host.contains("/") else { return nil }
        let withoutWWW = host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
        return withoutWWW.isEmpty ? nil : withoutWWW
    }

    private static func normalized(_ hosts: [String]) -> [String] {
        var seen: Set<String> = []
        return hosts.compactMap(normalizedHost(fromHost:)).filter { seen.insert($0).inserted }.sorted()
    }

    private func store(_ hosts: [String]) {
        disabledHosts = Self.normalized(hosts)
        defaults.set(disabledHosts, forKey: Keys.disabledHosts)
    }

    private enum Keys {
        static let enabled = "clearframe.contentBlocking.enabled"
        static let disabledHosts = "clearframe.contentBlocking.disabledHosts"
    }
}
