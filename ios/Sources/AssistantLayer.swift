import LimeghostCore
import LimeghostShared
import SwiftUI

/// Whether a drag down on the assistant's header closes it: far enough that
/// it was meant, or fast enough that it was flung.
enum AssistantDismissal {
    static let distance: CGFloat = 120
    static let flung: CGFloat = 300

    static func closes(translation: CGFloat, predictedEnd: CGFloat) -> Bool {
        translation >= distance || predictedEnd >= flung
    }
}
