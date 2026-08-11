import ClearframeCore
import Combine
import Foundation

enum OnboardingStep: Int, CaseIterable {
    case welcome
    case searchAndPrivacy
    case analyzePages
}

@MainActor
final class OnboardingController: ObservableObject {
    @Published private(set) var isPresented: Bool
    @Published private(set) var step: OnboardingStep = .welcome
    @Published private(set) var isInitialPresentation: Bool

    private let preferences: OnboardingPreferences

    init(preferences: OnboardingPreferences = OnboardingPreferences()) {
        self.preferences = preferences
        let needsIntroduction = !preferences.hasCompletedIntroduction
        isPresented = needsIntroduction
        isInitialPresentation = needsIntroduction
    }

    func advance() {
        guard let next = OnboardingStep(rawValue: step.rawValue + 1) else { return }
        step = next
    }

    func goBack() {
        guard let previous = OnboardingStep(rawValue: step.rawValue - 1) else { return }
        step = previous
    }

    func complete() {
        preferences.markIntroductionCompleted()
        isPresented = false
        step = .welcome
        isInitialPresentation = false
    }

    func revisit() {
        step = .welcome
        isInitialPresentation = false
        isPresented = true
    }
}
