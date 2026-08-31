import AppKit

/// The small questions the Profiles menu has to ask.
///
/// Drawn by hand rather than through `NSAlert`, for one reason: AppKit lays an
/// alert out centered only while its text is short, and quietly switches to a
/// left-aligned "wide" layout past an unpublished length. Both of these prompts
/// carry enough text to cross that line, so they came out left-aligned while
/// every other alert on the Mac is a centered column — icon, title, message.
/// This panel is that centered column, deterministically.
///
/// Still modal, still startable with no window in front (they are menu-bar
/// commands), still cancellable, and Return still means what it meant: the
/// name prompts default to their action, deletion defaults to Cancel so the
/// key that is easiest to hit is the one that changes nothing.
@MainActor
enum ProfilePrompts {
    /// Asks for a profile name. Returns nil if cancelled or left blank, so a
    /// profile is never created without one.
    static func askForName(title: String, message: String, initial: String) -> String? {
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 280, height: 24))
        field.stringValue = initial
        field.placeholderString = "Work, Personal, a client's name…"
        let confirmed = present(
            title: title,
            message: message,
            field: field,
            primaryTitle: title.hasPrefix("New") ? "Create" : "Rename",
            primaryIsDestructive: false,
            defaultsToPrimary: true
        )
        guard confirmed else { return nil }
        let typed = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return typed.isEmpty ? nil : typed
    }

    /// Deleting a profile takes its bookmarks, history and signed-in sessions
    /// with it and cannot be undone, so it says so plainly and defaults to
    /// keeping the profile.
    static func confirmDeletion(of name: String) -> Bool {
        present(
            title: "Delete the profile “\(name)”?",
            message: """
            Its bookmarks, history, site icons, per-site exceptions and \
            signed-in sessions are removed from this Mac. Downloaded files \
            are left alone. This cannot be undone.
            """,
            field: nil,
            primaryTitle: "Delete Profile",
            primaryIsDestructive: true,
            defaultsToPrimary: false
        )
    }

    // MARK: - The centered column

    /// Keeps the button targets alive for the length of the modal session.
    private final class Responder: NSObject {
        @objc func primary() { NSApp.stopModal(withCode: .OK) }
        @objc func cancel() { NSApp.stopModal(withCode: .cancel) }
    }

    private static func present(
        title: String,
        message: String,
        field: NSTextField?,
        primaryTitle: String,
        primaryIsDestructive: Bool,
        defaultsToPrimary: Bool
    ) -> Bool {
        let responder = Responder()

        let icon = NSImageView()
        icon.image = NSApp.applicationIconImage
        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.widthAnchor.constraint(equalToConstant: 64).isActive = true
        icon.heightAnchor.constraint(equalToConstant: 64).isActive = true

        let titleLabel = NSTextField(wrappingLabelWithString: title)
        titleLabel.font = .boldSystemFont(ofSize: 13)
        titleLabel.alignment = .center

        let messageLabel = NSTextField(wrappingLabelWithString: message)
        messageLabel.font = .systemFont(ofSize: 11.5)
        messageLabel.textColor = .secondaryLabelColor
        messageLabel.alignment = .center

        let cancelButton = NSButton(title: "Cancel", target: responder, action: #selector(Responder.cancel))
        let primaryButton = NSButton(title: primaryTitle, target: responder, action: #selector(Responder.primary))
        for button in [cancelButton, primaryButton] {
            button.bezelStyle = .rounded
            button.controlSize = .large
        }
        primaryButton.hasDestructiveAction = primaryIsDestructive
        cancelButton.keyEquivalent = "\u{1b}"

        let buttons = NSStackView(views: [cancelButton, primaryButton])
        buttons.orientation = .horizontal
        buttons.distribution = .fillEqually
        buttons.spacing = 10

        var rows: [NSView] = [icon, titleLabel, messageLabel]
        if let field { rows.append(field) }
        rows.append(buttons)

        let column = NSStackView(views: rows)
        column.orientation = .vertical
        column.alignment = .centerX
        column.spacing = 10
        column.setCustomSpacing(14, after: icon)
        column.edgeInsets = NSEdgeInsets(top: 18, left: 20, bottom: 20, right: 20)
        column.translatesAutoresizingMaskIntoConstraints = false

        let content = NSView()
        content.addSubview(column)
        NSLayoutConstraint.activate([
            column.topAnchor.constraint(equalTo: content.topAnchor),
            column.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            column.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            column.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            column.widthAnchor.constraint(equalToConstant: 340),
            messageLabel.widthAnchor.constraint(equalToConstant: 300),
            titleLabel.widthAnchor.constraint(lessThanOrEqualToConstant: 300),
            buttons.leadingAnchor.constraint(equalTo: column.leadingAnchor, constant: 20),
            buttons.trailingAnchor.constraint(equalTo: column.trailingAnchor, constant: -20),
        ])
        if let field {
            field.translatesAutoresizingMaskIntoConstraints = false
            field.widthAnchor.constraint(equalToConstant: 280).isActive = true
        }

        // Titled so it can become key — a text field cannot take keystrokes in
        // a borderless panel — but with the title bar dressed down to nothing,
        // which is also what gives the window its rounded alert corners.
        let window = NSWindow(
            contentRect: .zero,
            styleMask: [.titled, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.contentView = content
        window.setContentSize(content.fittingSize)
        window.center()

        if defaultsToPrimary {
            primaryButton.keyEquivalent = "\r"
        } else {
            cancelButton.keyEquivalent = "\r"
        }
        if let field { window.initialFirstResponder = field }

        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        let response = NSApp.runModal(for: window)
        window.orderOut(nil)
        _ = responder // keep alive until here
        return response == .OK
    }
}
