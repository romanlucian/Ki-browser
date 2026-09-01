import LimeghostCore
import Combine
import Foundation

/// The first-run introduction, one screen at a time.
///
/// Three steps until September 1, 2026, when it grew to seven so that the
/// features built since — the assistant panel, Compare, Reader, and the folder
/// icon sets — have somewhere to be seen. The founder chose the longer tour
/// over a short one knowing it is shown once and can be skipped at step one;
/// the menu entries added the same day are what make the shortcuts survive it.
enum OnboardingStep: Int, CaseIterable {
    case welcome
    case search
    case privacy
    case assistant
    case compare
    case reader
    case makeItYours

    var isLast: Bool { self == OnboardingStep.allCases.last }
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
