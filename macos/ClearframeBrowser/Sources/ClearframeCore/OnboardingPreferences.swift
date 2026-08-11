import Foundation

/// Local first-run completion state. This stores one boolean in the current
/// Mac user profile and carries no identifier, analytics, or remote state.
public struct OnboardingPreferences {
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public var hasCompletedIntroduction: Bool {
        defaults.bool(forKey: Keys.completedIntroduction)
    }

    public func markIntroductionCompleted() {
        defaults.set(true, forKey: Keys.completedIntroduction)
    }

    public func resetIntroduction() {
        defaults.removeObject(forKey: Keys.completedIntroduction)
    }

    private enum Keys {
        static let completedIntroduction = "clearframe.onboarding.completed.v1"
    }
}
