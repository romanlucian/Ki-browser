import Combine
import UIKit

/// Whether the software keyboard is on screen, from the system's own
/// notifications. The bar steps out of its way while it is.
@MainActor
final class KeyboardObserver: ObservableObject {
    @Published private(set) var isUp = false
    private var subscriptions: Set<AnyCancellable> = []

    init(center: NotificationCenter = .default) {
        center.publisher(for: UIResponder.keyboardWillShowNotification)
            .sink { [weak self] _ in self?.isUp = true }
            .store(in: &subscriptions)
        center.publisher(for: UIResponder.keyboardWillHideNotification)
            .sink { [weak self] _ in self?.isUp = false }
            .store(in: &subscriptions)
    }
}
