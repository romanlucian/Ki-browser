import AppKit
import SwiftUI

/// The address field, backed by `NSTextField` rather than SwiftUI's `TextField`.
///
/// Inline completion needs one thing SwiftUI does not expose: the ability to
/// insert the finished address and leave the added tail *selected*, so the next
/// keystroke replaces it instead of appending to it. That selection is the whole
/// interaction — it is what lets someone type "y", see "youtube.com", and either
/// press Return to go there or keep typing to mean something else. Without it a
/// completion is just text in the way.
///
/// Completion only ever runs when text is being added at the very end of the
/// field. Deleting, editing in the middle, or having a selection all leave the
/// text exactly as typed; nothing re-completes under a backspace, which is the
/// behaviour that makes an aggressive address bar infuriating.
struct AddressField: NSViewRepresentable {
    @Binding var text: String
    @Binding var isFocused: Bool
    let placeholder: String
    /// The finished address for what has been typed, or `nil` for none.
    let completion: (String) -> String?
    let onSubmit: () -> Void

    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField(string: text)
        field.delegate = context.coordinator
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = .systemFont(ofSize: 13)
        field.textColor = NSColor(ClearframeTheme.textPrimary)
        field.placeholderString = placeholder
        field.lineBreakMode = .byTruncatingTail
        field.cell?.usesSingleLineMode = true
        field.cell?.wraps = false
        field.cell?.isScrollable = true
        // The field is the only thing in the pill that takes typing; let it
        // stretch rather than pin itself to its current contents.
        field.setContentHuggingPriority(.defaultLow, for: .horizontal)
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return field
    }

    func updateNSView(_ field: NSTextField, context: Context) {
        context.coordinator.parent = self

        // Never overwrite what someone is in the middle of typing: a binding
        // update mid-edit would move the caret and discard the selection.
        if !context.coordinator.isEditing, field.stringValue != text {
            field.stringValue = text
        }
        if field.placeholderString != placeholder {
            field.placeholderString = placeholder
        }

        let isFirstResponder = field.currentEditor() != nil
        if isFocused, !isFirstResponder {
            DispatchQueue.main.async {
                guard let window = field.window else { return }
                window.makeFirstResponder(field)
                Coordinator.disableTextSubstitutions(in: field)
                // Focusing the address bar means "type a new address", so the
                // existing one is selected rather than appended to.
                field.currentEditor()?.selectAll(nil)
            }
        } else if !isFocused, isFirstResponder {
            DispatchQueue.main.async {
                field.window?.makeFirstResponder(nil)
            }
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: AddressField
        /// True between the first keystroke and the end of editing, so a
        /// binding update cannot stamp on live text.
        private(set) var isEditing = false
        /// Set for exactly one change when the reader is removing text.
        private var isRemovingText = false

        init(_ parent: AddressField) {
            self.parent = parent
        }

        func controlTextDidBeginEditing(_ notification: Notification) {
            isEditing = true
            if let field = notification.object as? NSTextField {
                Self.disableTextSubstitutions(in: field)
            }
            if !parent.isFocused {
                DispatchQueue.main.async { self.parent.isFocused = true }
            }
        }

        /// Turns off every macOS writing aid for this field.
        ///
        /// An address is not prose. With the system's "capitalize words"
        /// setting on, typing `youtube` becomes `Youtube`; smart quotes turn a
        /// query parameter's `"` into `"`, and dash substitution turns `--` in
        /// a URL into an em dash. Each of those silently changes an address
        /// into a different address, so the address bar opts out of all of
        /// them — which is what every other browser does too.
        static func disableTextSubstitutions(in field: NSTextField) {
            guard let editor = field.currentEditor() as? NSTextView else { return }
            editor.isAutomaticTextReplacementEnabled = false
            editor.isAutomaticSpellingCorrectionEnabled = false
            editor.isAutomaticQuoteSubstitutionEnabled = false
            editor.isAutomaticDashSubstitutionEnabled = false
            editor.isAutomaticDataDetectionEnabled = false
            editor.isAutomaticLinkDetectionEnabled = false
            editor.isAutomaticTextCompletionEnabled = false
            editor.isContinuousSpellCheckingEnabled = false
            editor.isGrammarCheckingEnabled = false
            editor.smartInsertDeleteEnabled = false
        }

        func controlTextDidEndEditing(_ notification: Notification) {
            isEditing = false
            isRemovingText = false
            if parent.isFocused {
                DispatchQueue.main.async { self.parent.isFocused = false }
            }
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            let typed = field.stringValue

            // A deletion is honoured exactly as made. Consuming the flag here
            // rather than on the keypress keeps one deletion from suppressing
            // the completion after it.
            if isRemovingText {
                isRemovingText = false
                publish(typed)
                return
            }

            guard let editor = field.currentEditor() else {
                publish(typed)
                return
            }
            let caret = editor.selectedRange
            let length = (typed as NSString).length
            // Only complete while adding to the end with nothing selected.
            guard caret.length == 0, caret.location == length else {
                publish(typed)
                return
            }
            guard let completed = parent.completion(typed),
                  completed.count > typed.count,
                  completed.hasPrefix(typed) else {
                publish(typed)
                return
            }

            field.stringValue = completed
            editor.selectedRange = NSRange(location: length, length: (completed as NSString).length - length)
            publish(completed)
        }

        /// Returns what the field means right now — the completion included, so
        /// Return opens the address on screen rather than the fragment typed.
        private func publish(_ value: String) {
            guard parent.text != value else { return }
            parent.text = value
        }

        func control(
            _ control: NSControl,
            textView: NSTextView,
            doCommandBy selector: Selector
        ) -> Bool {
            switch selector {
            case #selector(NSResponder.insertNewline(_:)):
                parent.onSubmit()
                return true
            case #selector(NSResponder.deleteBackward(_:)),
                 #selector(NSResponder.deleteForward(_:)),
                 #selector(NSResponder.deleteWordBackward(_:)),
                 #selector(NSResponder.deleteWordForward(_:)):
                isRemovingText = true
                return false
            case #selector(NSResponder.cancelOperation(_:)):
                // Escape drops a completion without dropping what was typed;
                // with nothing completed it gives the page back the keyboard.
                if textView.selectedRange.length > 0 {
                    let kept = (textView.string as NSString).substring(to: textView.selectedRange.location)
                    textView.string = kept
                    textView.selectedRange = NSRange(location: (kept as NSString).length, length: 0)
                    publish(kept)
                    return true
                }
                parent.isFocused = false
                return true
            case #selector(NSResponder.moveRight(_:)),
                 #selector(NSResponder.moveToEndOfLine(_:)):
                // Accepting a completion: keep it and put the caret after it,
                // the same gesture that dismisses one in every other browser.
                if textView.selectedRange.length > 0 {
                    let end = textView.selectedRange.location + textView.selectedRange.length
                    textView.selectedRange = NSRange(location: end, length: 0)
                    return true
                }
                return false
            default:
                return false
            }
        }
    }
}
