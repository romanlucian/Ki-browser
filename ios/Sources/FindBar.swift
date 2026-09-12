import LimeghostShared
import SwiftUI

/// Find in Page, in the bottom bar's place while it is open.
///
/// WebKit reports whether a match was found and nothing else — no position,
/// no total — so this bar says "No results" or says nothing at all, exactly
/// as the Mac's does. It never invents "3 of 12". It wears the bottom bar's
/// system look, because it stands where the bar stands; the two take the
/// theme together in the look step.
struct FindBar: View {
    @ObservedObject var find: PageFindController
    @FocusState private var fieldFocused: Bool

    /// "No results" when nothing matched, and nothing otherwise: not while
    /// idle, and not on a match, where the page's own highlight is the answer.
    static func outcomeText(_ outcome: PageFindController.Outcome) -> String? {
        outcome == .noResults ? "No results" : nil
    }

    /// The arrows step between matches, so they wait for one. The Mac greys
    /// them only while the field is empty; on a phone, with no count to show,
    /// greyed arrows are how the bar says there is nothing to step to.
    static func canStep(_ outcome: PageFindController.Outcome) -> Bool {
        outcome == .matched
    }

    var body: some View {
        HStack(spacing: 16) {
            HStack(spacing: 7) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Find in Page", text: $find.query)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.search)
                    .focused($fieldFocused)
                    .onSubmit { find.step(backwards: false) }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Capsule().fill(.quaternary))

            if let text = Self.outcomeText(find.outcome) {
                Text(text)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize()
            }

            Button { find.step(backwards: true) } label: {
                Image(systemName: "chevron.up")
            }
            .disabled(!Self.canStep(find.outcome))
            .accessibilityLabel("Previous match")

            Button { find.step(backwards: false) } label: {
                Image(systemName: "chevron.down")
            }
            .disabled(!Self.canStep(find.outcome))
            .accessibilityLabel("Next match")

            Button("Done") { find.close() }
                .fontWeight(.semibold)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .onAppear { fieldFocused = true }
        .onChange(of: find.focusRequest) { _, _ in fieldFocused = true }
        .onChange(of: find.query) { _, _ in find.queryChanged() }
    }
}
