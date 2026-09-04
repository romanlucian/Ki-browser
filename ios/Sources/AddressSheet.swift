import LimeghostCore
import LimeghostShared
import SwiftUI

/// Backs the address sheet: submitting what was typed, and completing it,
/// apart from the view that draws them, so a test can assert both without
/// standing up SwiftUI.
@MainActor
struct AddressSheetModel {
    private let workspace: BrowserWorkspace

    init(workspace: BrowserWorkspace) {
        self.workspace = workspace
    }

    /// Goes through `navigate`, the door Task 4 opened for exactly this. Not
    /// `open(_:)`, which guards on `WebURLPolicy.validatedURL` and silently
    /// refuses a bare host like `example.com` — the commonest thing typed
    /// here. Not `session.navigate` directly either, which would skip
    /// `makeRoomForPage()` and re-create the hand-applied rule that door was
    /// opened to remove.
    func submit(_ text: String) {
        workspace.navigate(text)
    }

    /// Local only: this profile's own history and bookmarks, nothing fetched
    /// while typing and no suggestion service contacted. `AddressCompletion`
    /// always returns a search row for non-empty input, even when nothing
    /// else matches — the search row sits behind the best place and ahead of
    /// the rest — which is its own deliberate design, not a gap for this
    /// layer to close.
    ///
    /// The Mac refuses to complete at all in a private tab, so a private
    /// session is never finished from the history of a normal one
    /// (`BrowserView.addressSuggestions`). Nothing on the phone can open a
    /// private tab yet, so there is no state here to guard; whichever task
    /// adds private browsing has to bring that guard with it.
    func suggestions(for typed: String) -> [AddressSuggestion] {
        AddressCompletion.suggestions(for: typed, in: workspace.dataStore.addressCandidates)
    }
}

/// Typing an address: a field, what this profile's own history and bookmarks
/// complete it to, and a way out. Presented as a sheet from `BottomBar`'s
/// address pill.
struct AddressSheet: View {
    private let model: AddressSheetModel
    private let dismiss: () -> Void

    /// Empty, rather than holding the address already on screen, for two
    /// reasons the Mac settled first.
    ///
    /// SwiftUI cannot select a `TextField`'s contents on iOS, and selecting
    /// them is the whole point of the Mac's own focus path
    /// (`BrowserView.focusAddressBar` sends `selectAll` after filling the
    /// field): it is what makes the first keystroke *replace* the address.
    /// Without it the caret sits after the address instead, so typing
    /// "bbc.com" asks for "https://example.com/bbc.com" — measured on the
    /// simulator, not assumed.
    ///
    /// And a field holding the current address completes it, so merely
    /// opening the sheet offered to search the web for the page already open.
    /// That is the exact defect the Mac records as fixed by matching on typed
    /// text alone (`BrowserView.addressSuggestions`). An empty field has
    /// neither problem, and the pill behind the sheet still says where you
    /// are.
    @State private var text = ""
    @FocusState private var isFocused: Bool

    init(workspace: BrowserWorkspace, dismiss: @escaping () -> Void) {
        self.model = AddressSheetModel(workspace: workspace)
        self.dismiss = dismiss
    }

    private var suggestions: [AddressSuggestion] {
        model.suggestions(for: text)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                TextField("Search or enter a website", text: $text)
                    .textFieldStyle(.roundedBorder)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.webSearch)
                    .submitLabel(.go)
                    .focused($isFocused)
                    .onSubmit { submit(text) }
                    .accessibilityLabel("Address")

                Button("Cancel", action: dismiss)
            }
            .padding()

            List(suggestions) { suggestion in
                Button {
                    open(suggestion)
                } label: {
                    row(for: suggestion)
                }
                .buttonStyle(.plain)
            }
            .listStyle(.plain)
        }
        // The sheet's own appearance is the request to type; nothing else
        // here asks for focus, so grabbing it on appear does not fight
        // another control for the keyboard.
        .onAppear { isFocused = true }
    }

    /// A search row's destination is decided by the engine at the moment it
    /// is used, so its `url` is empty by design — its `title` carries the
    /// typed text instead, and that is what goes to `navigate`.
    private func open(_ suggestion: AddressSuggestion) {
        switch suggestion.kind {
        case .search:
            submit(suggestion.title)
        case .place:
            submit(suggestion.url)
        }
    }

    private func submit(_ text: String) {
        model.submit(text)
        dismiss()
    }

    @ViewBuilder
    private func row(for suggestion: AddressSuggestion) -> some View {
        HStack(spacing: 12) {
            icon(for: suggestion.kind)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                Text(suggestion.title)
                    .lineLimit(1)
                    .foregroundStyle(.primary)
                // A search row's title is already the whole of what it shows
                // — its own address is nothing, so a second line here would
                // be an empty one.
                if case .place = suggestion.kind, !suggestion.url.isEmpty {
                    Text(suggestion.url)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
    }

    /// A visited or bookmarked place gets a mark of its own; a search row
    /// gets a magnifier, so the two are never confused for each other.
    @ViewBuilder
    private func icon(for kind: AddressSuggestion.Kind) -> some View {
        switch kind {
        case .search:
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
        case .place(let isBookmarked):
            Image(systemName: isBookmarked ? "star.fill" : "globe")
                .foregroundStyle(isBookmarked ? .orange : .secondary)
        }
    }
}
