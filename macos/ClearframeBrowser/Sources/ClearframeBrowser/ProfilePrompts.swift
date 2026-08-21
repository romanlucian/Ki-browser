import AppKit

/// The small questions the Profiles menu has to ask.
///
/// Standard AppKit alerts rather than sheets: these are menu-bar commands that
/// can be chosen with no window in front, and a sheet needs a window to attach
/// to. Each one is started by the person and each one can be cancelled.
@MainActor
enum ProfilePrompts {
    /// Asks for a profile name. Returns nil if cancelled or left blank, so a
    /// profile is never created without one.
    static func askForName(title: String, message: String, initial: String) -> String? {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: title.hasPrefix("New") ? "Create" : "Rename")
        alert.addButton(withTitle: "Cancel")

        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 280, height: 24))
        field.stringValue = initial
        field.placeholderString = "Work, Personal, a client's name…"
        alert.accessoryView = field
        alert.window.initialFirstResponder = field

        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        let typed = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return typed.isEmpty ? nil : typed
    }

    /// Deleting a profile takes its bookmarks, history and signed-in sessions
    /// with it and cannot be undone, so it says so plainly and defaults to
    /// keeping the profile.
    static func confirmDeletion(of name: String) -> Bool {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Delete the profile “\(name)”?"
        alert.informativeText = """
        Its bookmarks, history, site icons, per-site exceptions and signed-in \
        sessions are removed from this Mac. Downloaded files are left alone. \
        This cannot be undone.
        """
        // Cancel first, so the default button — the one Return presses — is
        // the one that changes nothing.
        alert.addButton(withTitle: "Cancel")
        alert.addButton(withTitle: "Delete Profile")
        return alert.runModal() == .alertSecondButtonReturn
    }
}
