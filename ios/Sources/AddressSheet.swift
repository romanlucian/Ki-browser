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
    ///
    /// **Nothing typed is not a request for anything.** The Mac's field
    /// arrives holding the address already on screen, so a bare Return there
    /// reloads the page you are on and means something. The phone's field is
    /// always empty when the sheet opens — deliberately, for the two reasons
    /// `AddressSheet.text` records — so the same keypress here hands
    /// `navigate` an empty string, `BrowserSession.resolve` returns no URL for
    /// it, and the session settles on `.failed`. That is not `.startPage`,
    /// which is half of what `showsGuide` requires, and nothing on this
    /// platform ever puts a tab back on its start page: there is no Home
    /// button and `startSurface` is never reset. So without this guard the
    /// first stray tap of Go discards the app's own opening screen for the
    /// life of that tab, with no way back to it. Doing nothing is the honest
    /// answer to being asked for nothing.
    /// Whether the tab in front is private, which is when the sheet shows one
    /// quiet line instead of anything from this profile's records.
    var isPrivateTab: Bool { workspace.selectedTab?.session.isPrivate == true }

    func submit(_ text: String) {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        workspace.navigate(text)
    }

    /// Local only: this profile's own history and bookmarks, nothing fetched
    /// while typing and no suggestion service contacted. `AddressCompletion`
    /// always returns a search row for non-empty input, even when nothing
    /// else matches — the search row sits behind the best place and ahead of
    /// the rest — which is its own deliberate design, not a gap for this
    /// layer to close.
    ///
    /// **Nothing is completed in a private tab.** Nothing is written there
    /// either way — a private session is excluded from history — but reading a
    /// saved history back onto the screen would work against what a private
    /// tab is for, which is why this is a guard rather than a reliance on
    /// there being nothing to show. It mirrors the Mac's
    /// `BrowserView.addressSuggestions` (`BrowserView.swift:752`), and
    /// `docs/privacy-and-safety.md` states it as a promise, so the two
    /// platforms are not free to disagree about it.
    ///
    /// It was missing for exactly as long as the phone had private tabs. This
    /// comment used to say there was no state here to guard and that whichever
    /// task added private browsing had to bring the guard with it; the tab
    /// switcher added them and did not. A note left for a future task is not a
    /// guard.
    func suggestions(for typed: String) -> [AddressSuggestion] {
        guard workspace.selectedTab?.session.isPrivate != true else { return [] }
        return AddressCompletion.suggestions(for: typed, in: workspace.dataStore.addressCandidates)
    }

    /// What was typed, laid out the way Safari lays it out — a top hit, a
    /// search, then bookmarks and history — from this profile's own records
    /// alone. Safari's middle section is suggestions its search engine sends
    /// back while you type; that section does not exist here, and the one
    /// search row is an action somebody chooses, sent only when it is tapped.
    ///
    /// **No new order.** `AddressCompletion` already returns the best place
    /// first, the search row behind it, and the rest after; this only draws the
    /// first place larger. Deciding afresh which result matters most would be
    /// a ranking this layer has no business making.
    func results(for typed: String) -> AddressResults {
        var places: [AddressSuggestion] = []
        var search: AddressSuggestion?
        for suggestion in suggestions(for: typed) {
            if suggestion.kind == .search { search = suggestion } else { places.append(suggestion) }
        }
        let topHit = places.isEmpty ? nil : places.removeFirst()
        let shown = Set(([topHit].compactMap { $0 } + places).map(\.url))
        // Looked up here rather than added to `AddressSuggestion`, which lives
        // in `LimeghostCore` and is the Mac's too: one line of text on a phone
        // is not a reason to change a type both platforms share. Only a real
        // visit counts — a bookmark never opened has a date that means nothing.
        let lastVisits = Dictionary(
            workspace.dataStore.addressCandidates
                .filter { shown.contains($0.url) && $0.visits > 0 }
                .map { ($0.url, $0.lastVisit) },
            uniquingKeysWith: { first, second in max(first, second) }
        )
        return AddressResults(topHit: topHit, search: search, places: places, lastVisits: lastVisits)
    }
}

/// The typing screen's contents, in the three parts it draws.
struct AddressResults: Equatable {
    /// `AddressCompletion`'s first place, drawn large.
    var topHit: AddressSuggestion?
    /// The one search row.
    var search: AddressSuggestion?
    /// Every other place, in `AddressCompletion`'s order.
    var places: [AddressSuggestion]
    /// When each shown place was last visited, by address.
    var lastVisits: [String: Date]

    var isEmpty: Bool { topHit == nil && search == nil && places.isEmpty }
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
    @Environment(\.scenePhase) private var scenePhase

    /// Held rather than rebuilt in `body`, since the view keeps no workspace
    /// of its own; it reads the tab in front each time it is asked.
    private let privacy: PrivacyCover

    init(workspace: BrowserWorkspace, dismiss: @escaping () -> Void) {
        self.model = AddressSheetModel(workspace: workspace)
        self.privacy = PrivacyCover(workspace: workspace)
        self.dismiss = dismiss
    }

    var body: some View {
        let results = model.results(for: text)
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if model.isPrivateTab { privateNote }
                if let top = results.topHit { topHitCard(top) }
                if let search = results.search { searchRow(search) }
                if !results.places.isEmpty { placesSection(results) }
            }
            .padding(.horizontal, 16)
            .padding(.top, 22)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(LimeghostTheme.bg1)
        // The field sits at the bottom, over the keyboard, because that is
        // where the address was a moment ago: the bar that opened this sheet is
        // at the bottom of the screen, and a field at the top made the eye and
        // the thumb jump the height of the phone to reach it. Safari moved its
        // field down for the same reason when it moved its bar.
        .safeAreaInset(edge: .bottom, spacing: 0) { field }
        // The sheet's own appearance is the request to type; nothing else
        // here asks for focus, so grabbing it on appear does not fight
        // another control for the keyboard.
        .onAppear { isFocused = true }
        // What is being typed in a private tab is as private as the page, and
        // the app switcher would photograph it just the same.
        .privacyCover(privacy.covers(scenePhase))
        // Limeghost's surfaces rather than the system's, like every other
        // sheet: this one was still following the phone into light mode.
        .limeghostListSheet()
    }

    private var field: some View {
        HStack(spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(LimeghostTheme.textTertiary)
                TextField("Search or enter a website", text: $text)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.webSearch)
                    .submitLabel(.go)
                    .focused($isFocused)
                    .onSubmit { submit(text) }
                    .foregroundStyle(LimeghostTheme.textPrimary)
                    .accessibilityLabel("Address")
                if !text.isEmpty {
                    Button { text = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .frame(width: 32, height: 44)
                            .contentShape(Rectangle())
                    }
                    .foregroundStyle(LimeghostTheme.textTertiary)
                    .accessibilityLabel("Clear")
                }
            }
            .padding(.leading, 14)
            .frame(height: 44)
            .background(Capsule().fill(LimeghostTheme.bg3))

            Button(action: dismiss) {
                Image(systemName: "xmark")
                    .font(.body.weight(.semibold))
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(LimeghostTheme.bg3))
            }
            .foregroundStyle(LimeghostTheme.textPrimary)
            .accessibilityLabel("Cancel")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(LimeghostTheme.bg1)
    }

    /// Shown instead of anything from this profile's records. It says why the
    /// sheet is empty, so an empty sheet does not look like a broken one.
    private var privateNote: some View {
        Label("Private — your history and bookmarks aren\u{2019}t shown here", systemImage: "eye.slash")
            .font(.footnote)
            .foregroundStyle(LimeghostTheme.textTertiary)
    }

    /// The best place, drawn large. Nothing here decides it is the best:
    /// `AddressCompletion` already put it first.
    private func topHitCard(_ suggestion: AddressSuggestion) -> some View {
        Button { open(suggestion) } label: {
            HStack(spacing: 14) {
                SiteIconView(urlString: Self.withScheme(suggestion.url), size: 32)
                VStack(alignment: .leading, spacing: 3) {
                    Text(suggestion.title)
                        .font(.headline)
                        .foregroundStyle(LimeghostTheme.textPrimary)
                        .lineLimit(1)
                    Text(Self.host(of: suggestion.url))
                        .font(.subheadline)
                        .foregroundStyle(LimeghostTheme.textSecondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(16)
            .background(RoundedRectangle(cornerRadius: LimeghostTheme.radius14).fill(LimeghostTheme.bg2))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint("Top hit")
    }

    /// One row, and an action: nothing is sent while typing, and this sends
    /// the typed text to the search engine only when it is tapped.
    private func searchRow(_ suggestion: AddressSuggestion) -> some View {
        Button { open(suggestion) } label: {
            HStack(spacing: 14) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(LimeghostTheme.textSecondary)
                    .frame(width: 22)
                Text("Search for \u{201C}\(suggestion.title)\u{201D}")
                    .foregroundStyle(LimeghostTheme.textPrimary)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func placesSection(_ results: AddressResults) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Bookmarks and History")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(LimeghostTheme.textTertiary)
                .padding(.bottom, 4)
            ForEach(results.places) { place in
                Button { open(place) } label: {
                    HStack(spacing: 14) {
                        SiteIconView(urlString: Self.withScheme(place.url), size: 22)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(place.title)
                                .foregroundStyle(LimeghostTheme.textPrimary)
                                .lineLimit(1)
                            Text(Self.detail(for: place, lastVisit: results.lastVisits[place.url]))
                                .font(.caption)
                                .foregroundStyle(LimeghostTheme.textSecondary)
                                .lineLimit(1)
                        }
                        Spacer(minLength: 0)
                    }
                    .frame(minHeight: 52)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
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

    /// A place's address arrives **without a scheme** — `example.com/`, not
    /// `https://example.com/` — because that is how `AddressCandidate` stores
    /// it, and `URL(string:)` finds no host in it at all. The Mac's own list
    /// (`AddressSuggestionsView`) builds `"https://\(suggestion.url)"` before
    /// asking for an icon; this did not at first, so every icon here was handed
    /// an empty host and every site drew the same grey square.
    static func withScheme(_ address: String) -> String {
        address.contains("://") ? address : "https://" + address
    }

    /// The host, without `www.` — the same trim the bar's pill makes.
    static func host(of address: String) -> String {
        guard let host = URL(string: withScheme(address))?.host else { return address }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

    /// "example.com · Bookmark · Visited 2 weeks ago", as much of it as is
    /// true. A place with no recorded visit says nothing about when.
    static func detail(for place: AddressSuggestion, lastVisit: Date?, now: Date = Date()) -> String {
        var parts = [host(of: place.url)]
        if case .place(let isBookmarked) = place.kind, isBookmarked { parts.append("Bookmark") }
        if let lastVisit {
            let relative = RelativeDateTimeFormatter()
            relative.unitsStyle = .full
            parts.append("Visited " + relative.localizedString(for: lastVisit, relativeTo: now))
        }
        return parts.joined(separator: " \u{00B7} ")
    }
}
