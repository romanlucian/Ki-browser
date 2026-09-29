import LimeghostCore
import LimeghostShared
import SwiftUI
import UniformTypeIdentifiers

/// What a chosen file holds, planned against what is already saved: the
/// phone's copy of the Mac's `PreviewInfo`. It keeps the parsed import and the
/// collection it was read against rather than one fixed plan, because choosing
/// the other place re-plans the whole tree — a walk over what is already in
/// memory — and nothing is written until Import.
struct BookmarkImportPreview {
    let fileName: String
    let imported: BookmarkImport
    let existing: BookmarkCollection
    /// Entries the file held that could not be kept, most often an unsafe or
    /// missing address, counted so the result can say so.
    let unusableCount: Int

    /// "Imported from a file — 29 September 2026", as the Mac names a file's
    /// import: the file's own name is usually "Bookmarks", which says less.
    var importFolderTitle: String {
        BookmarkImportFolderNaming.destinationFolderTitle(sourceLabel: "a file")
    }

    func plan(_ placement: BookmarkImportPlacement) -> BookmarkImportPlan {
        BookmarkImportMergePlanner.plan(imported, into: existing, placement: placement, importFolderTitle: importFolderTitle)
    }
}

/// Import Bookmarks on the phone. Every step is the Mac's own code in the
/// shared targets — `BookmarkSourceLoader` reads the file and words every
/// failure, `BookmarkImportMergePlanner` plans it, `BookmarkImportApplier`
/// applies and undoes it — so the two apps cannot disagree about what an
/// import did. This only holds the store they act on.
@MainActor
struct BookmarkImportModel {
    let store: BrowserDataStore

    enum Reading {
        case preview(BookmarkImportPreview)
        /// A sentence to show as it is: the loader never hands back a raw
        /// parser error.
        case problem(String)
    }

    /// A file from the Files picker. Its address points outside the app's own
    /// container, so it may be read only between these two calls.
    func read(_ url: URL) -> Reading {
        let granted = url.startAccessingSecurityScopedResource()
        defer { if granted { url.stopAccessingSecurityScopedResource() } }
        return reading(BookmarkSourceLoader.load(from: url), fileName: url.lastPathComponent)
    }

    /// The bytes themselves, for a caller that already has them.
    func read(_ data: Data, fileName: String) -> Reading {
        reading(BookmarkSourceLoader.load(data), fileName: fileName)
    }

    /// Planned against the bookmarks saved at this moment: a plan may only be
    /// applied to the collection it was read against.
    private func reading(_ outcome: BookmarkSourceLoader.Outcome, fileName: String) -> Reading {
        switch outcome {
        case .success(let loaded):
            return .preview(BookmarkImportPreview(
                fileName: fileName,
                imported: loaded.imported,
                existing: BookmarkCollection(folders: store.bookmarkFolders, bookmarks: store.bookmarks),
                unusableCount: loaded.unusableCount
            ))
        case .failure(let message):
            return .problem(message)
        }
    }

    /// Where the import goes unless the person says otherwise, by the Mac's
    /// rule: nothing saved yet, so the old bar becomes the top; something
    /// already arranged, so one folder that can be removed in one go.
    func suggestedPlacement(for preview: BookmarkImportPreview) -> BookmarkImportPlacement {
        BookmarkImportMergePlanner.recommendedPlacement(for: preview.existing)
    }

    func apply(_ plan: BookmarkImportPlan) -> BookmarkImportApplyResult {
        BookmarkImportApplier.apply(plan, into: store)
    }

    func undo(_ result: BookmarkImportApplyResult) {
        BookmarkImportApplier.undo(result, in: store)
    }
}

/// Import Bookmarks' words. The Mac's sentences, with its bookmarks bar made
/// the top of Bookmarks — a phone has no bar — and a guide to getting the file
/// that names the real ways out of Safari on an iPhone and off a computer.
enum BookmarkImportWording {
    static let fromSafari = "In Settings, open Apps › Safari, then Export, and export your bookmarks. Safari saves a ZIP file in Downloads — open it in Files to unpack it, then choose the bookmarks file inside."
    static let fromComputer = "In Chrome, Safari, Firefox or Limeghost on a computer, choose Export Bookmarks to save an HTML file, then send it to this iPhone with AirDrop or save it to iCloud Drive."
    static let guideFootnote = "Limeghost reads only the file you choose, and nothing changes until you have seen what it found and tapped Import."

    static func placementTitle(_ placement: BookmarkImportPlacement) -> String {
        switch placement {
        case .bookmarksBar: return "At the top of Bookmarks"
        case .singleFolder: return "In one new folder"
        }
    }

    /// What will actually happen, and never more than the applier does.
    static func placementExplanation(_ plan: BookmarkImportPlan) -> String {
        let importFolderTitle = plan.importFolderIndex.map { plan.folders[$0].title }
        switch plan.placement {
        case .bookmarksBar:
            var text = "What that browser kept on its bookmarks bar goes straight to the top of Bookmarks, beside what's already there"
            if let importFolderTitle {
                text += ", and everything else goes into “\(importFolderTitle)”"
            }
            return text + ". Nothing already saved is moved, renamed, or replaced."
        case .singleFolder:
            let name = importFolderTitle.map { "“\($0)”" } ?? "one new folder"
            return "Everything lands in \(name), organized the same way it already was. Nothing already saved is moved, renamed, or replaced."
        }
    }

    /// Named before the import runs, so two folders with one name at the top
    /// are a decision rather than a surprise.
    static func collisionWarning(_ titles: [String]) -> String {
        let quoted = titles.map { "“\($0)”" }
        let list: String
        switch quoted.count {
        case 1: list = quoted[0]
        case 2: list = "\(quoted[0]) and \(quoted[1])"
        default: list = quoted.dropLast().joined(separator: ", ") + ", and " + quoted[quoted.count - 1]
        }
        let what = titles.count == 1 ? "a folder with that name" : "folders with those names"
        return "You already have \(what) at the top of Bookmarks: \(list). Limeghost won't merge into \(titles.count == 1 ? "it" : "them") or rename anything, so you'll see both — yours untouched, and the imported one beside it."
    }

    /// Where the bookmarks went, which at the top can be two places at once.
    static func resultHeadline(_ result: BookmarkImportApplyResult) -> String {
        let added = counted(result.addedCount, "bookmark")
        switch result.placement {
        case .singleFolder:
            guard let title = result.importFolderTitle else { return "\(added) added." }
            return "\(added) added to “\(title)”."
        case .bookmarksBar:
            let folders = counted(result.createdBarFolderCount, "folder")
            if let title = result.importFolderTitle, result.createdBarFolderCount > 0 {
                return "\(added) added — \(folders) at the top of Bookmarks, and the rest in “\(title)”."
            }
            if let title = result.importFolderTitle {
                return "\(added) added to “\(title)”."
            }
            return "\(added) added at the top of Bookmarks."
        }
    }

    /// Not "nothing else is touched": a bookmark moved into an imported
    /// folder afterwards is kept, one level up. The Mac's own caveat.
    static func undoExplanation(_ result: BookmarkImportApplyResult) -> String {
        let created = result.createdFolderIDs.compactMap { $0 }.count
        let folders = created == 0 ? "" : "\(counted(created, "folder")) and "
        return "Undo Import removes the \(folders)\(counted(result.addedCount, "bookmark")) this import added. If you've moved any of your own bookmarks into them since, those are kept and move up one level."
    }

    static func counted(_ count: Int, _ singular: String, plural: String? = nil) -> String {
        "\(count) \(count == 1 ? singular : (plural ?? "\(singular)s"))"
    }
}

/// Import Bookmarks, over Bookmarks: a guide to getting the file, the Files
/// picker, a preview with the one decision worth asking — where the bookmarks
/// go — and the result, with Undo. Reached from the "Import" button at the
/// bottom of Bookmarks, and from the empty list, which is the moment somebody
/// wants it; the founder chose both on September 29, 2026.
struct BookmarkImportSheet: View {
    private let model: BookmarkImportModel
    @Environment(\.dismiss) private var dismiss

    @State private var stage: Stage = .guide
    @State private var isChoosingFile = false
    @State private var placement: BookmarkImportPlacement = .singleFolder

    private enum Stage {
        case guide
        case preview(BookmarkImportPreview)
        case result(BookmarkImportApplyResult, unusableCount: Int)
        case problem(String)
    }

    init(store: BrowserDataStore) {
        model = BookmarkImportModel(store: store)
    }

    var body: some View {
        NavigationStack {
            List {
                switch stage {
                case .guide: guide
                case .preview(let preview): previewSections(preview)
                case .result(let result, let unusableCount): resultSections(result, unusableCount: unusableCount)
                case .problem(let message): problemSections(message)
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbar }
            .fileImporter(isPresented: $isChoosingFile, allowedContentTypes: [.html, .zip, .json, .data]) { chosen in
                guard case .success(let url) = chosen else { return }
                show(model.read(url))
            }
        }
        .limeghostListSheet()
    }

    private var title: String {
        switch stage {
        case .guide, .preview: return "Import Bookmarks"
        case .result: return "Import Complete"
        case .problem: return "Couldn't Import That"
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        switch stage {
        case .guide, .problem:
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
        case .preview(let preview):
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                let plan = preview.plan(placement)
                if plan.isEmpty {
                    Button("Done") { dismiss() }
                } else {
                    Button("Import") {
                        stage = .result(model.apply(plan), unusableCount: preview.unusableCount)
                    }
                }
            }
        case .result:
            ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
        }
    }

    // MARK: - Stages

    @ViewBuilder
    private var guide: some View {
        Section("From Safari on this iPhone") {
            Text(BookmarkImportWording.fromSafari).listRowBackground(LimeghostTheme.bg2)
        }
        Section("From a computer") {
            Text(BookmarkImportWording.fromComputer).listRowBackground(LimeghostTheme.bg2)
        }
        Section {
            Button("Choose File\u{2026}") { isChoosingFile = true }
                .frame(maxWidth: .infinity)
                .fontWeight(.semibold)
                .listRowBackground(LimeghostTheme.bg2)
        } footer: {
            Text(BookmarkImportWording.guideFootnote)
        }
    }

    @ViewBuilder
    private func previewSections(_ preview: BookmarkImportPreview) -> some View {
        let plan = preview.plan(placement)
        Section(preview.fileName) {
            if plan.isEmpty {
                Text("Every bookmark in this file — \(BookmarkImportWording.counted(plan.sourceBookmarkCount, "bookmark")) in all — is already saved. There's nothing new to import.")
                    .listRowBackground(LimeghostTheme.bg2)
            } else {
                line("Found", "\(BookmarkImportWording.counted(plan.sourceBookmarkCount, "bookmark")) in \(BookmarkImportWording.counted(plan.sourceFolderCount, "folder"))")
                line("Will be added", BookmarkImportWording.counted(plan.addedCount, "bookmark"))
                if plan.skippedExistingCount > 0 {
                    line("Already saved, left alone", BookmarkImportWording.counted(plan.skippedExistingCount, "bookmark"))
                }
                if plan.duplicateWithinImportCount > 0 {
                    line("Repeated in the file, kept once", BookmarkImportWording.counted(plan.duplicateWithinImportCount, "bookmark"))
                }
            }
        }
        if !plan.isEmpty {
            // The one decision worth asking about, always shown: somebody
            // arriving from another browser and somebody topping up a list
            // they already arranged want opposite things, and only they know
            // which they are.
            Section {
                // Two rows drawn here rather than an inline `Picker`: its tick
                // drew in iOS blue beside Limeghost's green buttons, and
                // neither the sheet's tint nor one on the picker reached it.
                ForEach(BookmarkImportPlacement.allCases, id: \.self) { option in
                    Button {
                        placement = option
                    } label: {
                        HStack {
                            Text(BookmarkImportWording.placementTitle(option))
                                .foregroundStyle(LimeghostTheme.textPrimary)
                            Spacer()
                            if option == placement {
                                Image(systemName: "checkmark")
                                    .fontWeight(.semibold)
                                    .foregroundStyle(LimeghostTheme.accent)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .listRowBackground(LimeghostTheme.bg2)
                    .accessibilityAddTraits(option == placement ? [.isButton, .isSelected] : .isButton)
                }
            } header: {
                Text("Where should these go?")
            } footer: {
                VStack(alignment: .leading, spacing: 8) {
                    Text(BookmarkImportWording.placementExplanation(plan))
                    if !plan.barTitleCollisions.isEmpty {
                        Text(BookmarkImportWording.collisionWarning(plan.barTitleCollisions))
                            .foregroundStyle(.orange)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func resultSections(_ result: BookmarkImportApplyResult, unusableCount: Int) -> some View {
        Section {
            Text(BookmarkImportWording.resultHeadline(result)).listRowBackground(LimeghostTheme.bg2)
            if result.skippedExistingCount > 0 {
                Text("\(BookmarkImportWording.counted(result.skippedExistingCount, "address", plural: "addresses")) already saved — left exactly where they were.")
                    .listRowBackground(LimeghostTheme.bg2)
            }
            if result.duplicateWithinImportCount > 0 {
                Text("\(BookmarkImportWording.counted(result.duplicateWithinImportCount, "bookmark")) repeated in the file — added once.")
                    .listRowBackground(LimeghostTheme.bg2)
            }
            if unusableCount > 0 {
                Text("\(BookmarkImportWording.counted(unusableCount, "entry", plural: "entries")) couldn't be used.")
                    .listRowBackground(LimeghostTheme.bg2)
            }
        }
        if !result.createdBookmarkIDs.isEmpty {
            Section {
                Button("Undo Import", role: .destructive) {
                    model.undo(result)
                    dismiss()
                }
                .listRowBackground(LimeghostTheme.bg2)
            } footer: {
                Text(BookmarkImportWording.undoExplanation(result))
            }
        }
    }

    @ViewBuilder
    private func problemSections(_ message: String) -> some View {
        Section {
            Text(message).listRowBackground(LimeghostTheme.bg2)
        }
        Section {
            Button("Choose Another File\u{2026}") { isChoosingFile = true }
                .frame(maxWidth: .infinity)
                .listRowBackground(LimeghostTheme.bg2)
        }
    }

    private func line(_ label: String, _ value: String) -> some View {
        LabeledContent(label, value: value)
            .listRowBackground(LimeghostTheme.bg2)
    }

    /// Seeds the placement from what is already saved, then leaves it to the
    /// person for as long as this preview is open.
    private func show(_ reading: BookmarkImportModel.Reading) {
        switch reading {
        case .preview(let preview):
            placement = model.suggestedPlacement(for: preview)
            stage = .preview(preview)
        case .problem(let message):
            stage = .problem(message)
        }
    }
}
