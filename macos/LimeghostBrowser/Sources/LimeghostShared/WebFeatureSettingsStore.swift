import Combine
import Foundation

/// Two local switches for WebKit capabilities that are policy rather than
/// plumbing: whether navigations are upgraded to HTTPS where the host is known
/// to support it, and whether Safari's Web Inspector may attach to Limeghost's
/// pages. Both live here rather than in the browsing-data store because neither
/// is browsing data — clearing local data must not silently change them.
@MainActor
public final class WebFeatureSettingsStore: ObservableObject {
    @Published public private(set) var upgradesToHTTPS: Bool
    @Published public private(set) var showsDeveloperFeatures: Bool

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        // On by default: an upgrade the browser can make silently is one the
        // person should not have to ask for.
        upgradesToHTTPS = defaults.object(forKey: Keys.upgradeToHTTPS) as? Bool ?? true
        // Off by default: attaching an inspector to someone's browsing is a
        // developer's choice, not a default posture.
        showsDeveloperFeatures = defaults.object(forKey: Keys.developerExtras) as? Bool ?? false
    }

    public func setUpgradesToHTTPS(_ value: Bool) {
        guard value != upgradesToHTTPS else { return }
        upgradesToHTTPS = value
        defaults.set(value, forKey: Keys.upgradeToHTTPS)
    }

    public func setShowsDeveloperFeatures(_ value: Bool) {
        guard value != showsDeveloperFeatures else { return }
        showsDeveloperFeatures = value
        defaults.set(value, forKey: Keys.developerExtras)
    }

    private enum Keys {
        static let upgradeToHTTPS = "clearframe.upgradeToHTTPS"
        static let developerExtras = "clearframe.developerExtras"
    }
}
