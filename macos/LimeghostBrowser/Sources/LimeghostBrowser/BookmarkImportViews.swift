import AppKit
import LimeghostCore
import SwiftUI

/// What actually happened when a `BookmarkImportPlan` was applied to the
/// store: the real folder and bookmark ids it created, in the order it
/// created them. Carrying the ids (not just counts) is what makes `undo`
/// possible, and is why undo works the same whether the import landed in
/// one folder or across the bar — there is no wrapper it depends on.
struct BookmarkImportApplyResult: Equatable {
    let placement: BookmarkImportPlacement
    /// The dated container's id and title, when the import created one.
    /// Both `nil` together: under bar placement with nothing left over
    /// there is no such folder, and no screen should name one that does not
    /// exist.
    let importFolderID: UUID?
    let importFolderTitle: String?
    /// Parent-before-child: the same order `BookmarkImportPlan.folders`
    /// listed them in, which is the order they were created in.
    ///
    /// `nil` at a slot means that folder could not be created and its
    /// children were filed one level up. Deliberately not "the parent's id
    /// instead" — that would make undo delete a folder this import did not
    /// create, which under bar placement would be one of the person's own.
    let createdFolderIDs: [UUID?]
    let createdBookmarkIDs: [UUID]
    let skippedExistingCount: Int
    let duplicateWithinImportCount: Int

    var addedCount: Int { createdBookmarkIDs.count }
    /// How many of the source's *own* bar folders now sit on the bar.
    /// Excludes the dated container, which is also a top-level folder but is
    /// Limeghost's own doing rather than something the person recognizes
    /// from the browser they came from — counting it would make the result
    /// screen name it twice.
    var createdBarFolderCount: Int = 0
}

/// Applies a `BookmarkImportPlan` to a `BrowserDataStore`, and can undo
/// exactly what it applied. Both directions are built entirely from the
/// store's own existing, already-tested primitives — creating a folder,
/// adding a bookmark, removing a bookmark, and deleting an (by then empty)
/// folder without disturbing its parent — so undoing an import needs no
/// separate "delete with contents" capability that the rest of the app does
/// not also have.
@MainActor
enum BookmarkImportApplier {
    /// Only `createBookmarkFolder` and `addBookmark` are used here, and both
    /// only ever append to a sibling row without renumbering it. Never reach
    /// for `moveBookmarkFolder(_:toIndex:)` or `moveBookmark(_:toIndex:)` in
    /// this file: they renumber an entire row of siblings, and under bar
    /// placement that row is the person's own bookmarks bar.
    ///
    /// A plan may only be applied to the collection it was planned against.
    /// It was built knowing which addresses that collection already held.
    static func apply(_ plan: BookmarkImportPlan, into store: BrowserDataStore) -> BookmarkImportApplyResult {
        // The single most important rule this whole feature exists to
        // protect: an address already saved is skipped, never re-added, so
        // `BookmarkCollection.addBookmark`'s replace-on-matching-URL
        // behavior never has a chance to move or rename an existing
        // bookmark. `plan` already excludes every such address — this
        // function only ever creates brand-new records. That reasoning is
        // unchanged by placement: the skip is keyed on the address, and
        // where a new bookmark lands has nothing to do with it.
        guard !plan.isEmpty else { return emptyResult(for: plan) }

        var createdFolderIDs: [UUID?] = []
        var createdBookmarkIDs: [UUID] = []
        var createdBarFolderCount = 0

        // One write for the whole import instead of one per record. Every
        // call below still updates the store's published records
        // immediately; only the encoding and the disk write wait for the
        // end.
        store.performBatch {
        for (index, planned) in plan.folders.enumerated() {
            // `flatMap`, not `map`: a parent that could not be created
            // leaves its children filed one level up rather than trapping.
            let parentID = planned.parentIndex.flatMap { createdFolderIDs[$0] }
            let created = store.createBookmarkFolder(
                title: planned.title,
                iconID: LimeghostIconCatalog.defaultIconID,
                colorID: nil,
                parentID: parentID
            )
            createdFolderIDs.append(created?.id)
            if created != nil, planned.parentIndex == nil, index != plan.importFolderIndex {
                createdBarFolderCount += 1
            }
        }

        for planned in plan.bookmarks {
            let parentID = planned.parentIndex.flatMap { createdFolderIDs[$0] }
            if let created = store.addBookmark(title: planned.title, url: planned.url, folderID: parentID) {
                createdBookmarkIDs.append(created.id)
            }
        }
        }

        let importFolderID = plan.importFolderIndex.flatMap { createdFolderIDs[$0] }
        return BookmarkImportApplyResult(
            placement: plan.placement,
            importFolderID: importFolderID,
            importFolderTitle: importFolderID == nil ? nil : plan.importFolderIndex.map { plan.folders[$0].title },
            createdFolderIDs: createdFolderIDs,
            createdBookmarkIDs: createdBookmarkIDs,
            skippedExistingCount: plan.skippedExistingCount,
            duplicateWithinImportCount: plan.duplicateWithinImportCount,
            createdBarFolderCount: createdBarFolderCount
        )
    }

    private static func emptyResult(for plan: BookmarkImportPlan) -> BookmarkImportApplyResult {
        BookmarkImportApplyResult(
            placement: plan.placement,
            importFolderID: nil,
            importFolderTitle: nil,
            createdFolderIDs: [],
            createdBookmarkIDs: [],
            skippedExistingCount: plan.skippedExistingCount,
            duplicateWithinImportCount: plan.duplicateWithinImportCount,
            createdBarFolderCount: 0
        )
    }

    /// Removes every bookmark this import created, then deletes every folder
    /// it created, deepest first. By the time any one folder's turn comes,
    /// its own bookmarks are already gone and every subfolder has already
    /// been removed, so it is genuinely empty — the existing
    /// preserve-contents delete has nothing left to preserve and simply
    /// removes it, the same way it already does for any other empty folder.
    ///
    /// Nothing this import did not create is ever touched, and because both
    /// creation primitives only appended, every record the person already
    /// had comes back to its exact previous position rather than merely its
    /// previous folder.
    ///
    /// The one thing this cannot promise: a bookmark the person moved into
    /// an imported folder *after* importing is kept, but ends up one level
    /// up, because deleting its folder preserves its contents by reparenting
    /// them. The result screen says so rather than promising nothing moves.
    static func undo(_ result: BookmarkImportApplyResult, in store: BrowserDataStore) {
        store.performBatch {
        for bookmarkID in result.createdBookmarkIDs {
            guard let bookmark = store.bookmarks.first(where: { $0.id == bookmarkID }) else { continue }
            store.removeBookmark(bookmark)
        }
        for folderID in result.createdFolderIDs.reversed() {
            guard let folderID, let folder = store.bookmarkFolder(id: folderID) else { continue }
            store.deleteBookmarkFolderPreservingContents(folder)
        }
        }
    }
}

/// The Bookmarks-menu "Import Bookmarks…" flow and the bookmarks home's own
/// entry point, in one shared sheet: choose a source, review exactly what
/// will happen, then see (and if needed undo) the result. Nothing touches
/// the store until Import is pressed.
struct BookmarkImportSheet: View {
    @ObservedObject var store: BrowserDataStore
    /// Called when the sheet is done for good, with whether an import
    /// actually happened — `true` only once the result screen was reached,
    /// `false` for a plain Cancel or an empty "nothing to import" dismissal.
    /// The toolbar's menu-triggered presentation opens the bookmarks home
    /// only on `true`, so clicking Import Bookmarks and immediately
    /// cancelling never yanks the person off the page they were reading.
    let finished: (Bool) -> Void

    @State private var stage: Stage = .chooseSource
    @State private var sources: [DetectedBookmarkSource] = []
    /// Seeded per preview from what is already on the bar, then owned by the
    /// person for as long as that preview is open.
    @State private var placement: BookmarkImportPlacement = .singleFolder

    private enum Stage {
        case chooseSource
        case safariGuidance
        case preview(PreviewInfo)
        case result(BookmarkImportApplyResult, unusableCount: Int)
        case problem(String)
    }

    /// Everything the preview needs to re-plan on demand. It keeps the
    /// parsed import and the collection snapshot it was read against rather
    /// than one fixed plan, because changing the placement changes the whole
    /// tree — and re-planning is a pure walk over a tree already in memory,
    /// with nothing written until Import is pressed.
    private struct PreviewInfo {
        let sourceRowTitle: String
        let folderNamingLabel: String
        let imported: BookmarkImport
        let existing: BookmarkCollection
        let unusableCount: Int

        var importFolderTitle: String {
            BookmarkImportFolderNaming.destinationFolderTitle(sourceLabel: folderNamingLabel)
        }

        func plan(_ placement: BookmarkImportPlacement) -> BookmarkImportPlan {
            BookmarkImportMergePlanner.plan(
                imported,
                into: existing,
                placement: placement,
                importFolderTitle: importFolderTitle
            )
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            switch stage {
            case .chooseSource: chooseSourceStage
            case .safariGuidance: safariGuidanceStage
            case .preview(let info): previewStage(info)
            case .result(let result, let unusableCount): resultStage(result, unusableCount: unusableCount)
            case .problem(let message): problemStage(message)
            }
        }
        .padding(22)
        .frame(width: 480)
        .onAppear {
            if sources.isEmpty { sources = BookmarkImportSourceDiscovery.detectSources() }
        }
    }

    // MARK: - Choose source

    private var chooseSourceStage: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Import bookmarks")
                .font(.title2.bold())
            Text("Choose where to import from. Nothing changes until you review what was found and choose Import.")
                .font(.callout)
                .foregroundStyle(.secondary)
            VStack(spacing: 6) {
                ForEach(sources) { source in
                    sourceRow(source)
                }
            }
            HStack {
                Spacer()
                Button("Cancel") { finished(false) }
            }
        }
    }

    private func sourceRow(_ source: DetectedBookmarkSource) -> some View {
        Button { select(source) } label: {
            HStack(spacing: 10) {
                Image(systemName: symbol(for: source.kind))
                    .frame(width: 20)
                    .foregroundStyle(.secondary)
                Text(source.title)
                    .font(.callout)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 12)
            .frame(height: 36)
            .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 8))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(source.title)
    }

    private func symbol(for kind: DetectedBookmarkSource.Kind) -> String {
        switch kind {
        case .chromium: return "globe"
        case .safari: return "safari"
        case .file: return "folder"
        }
    }

    private func select(_ source: DetectedBookmarkSource) {
        switch source.kind {
        case .safari:
            attemptSafariRead()
        case .file:
            chooseFile(sourceLabelOverride: nil)
        case .chromium:
            guard let url = source.bookmarksFileURL else { return }
            loadAndPreview(from: url, sourceRowTitle: source.title, folderNamingLabel: source.folderNamingLabel)
        }
    }

    // MARK: - Safari

    private func attemptSafariRead() {
        // `~/Library/Safari/` is TCC-protected: reading it fails until the
        // person grants Full Disk Access, and there is no API to request
        // that. Even on the rare machine where it is already granted,
        // Limeghost does not parse the plist — its schema is recalled from
        // documentation, not verified against a real file this session (see
        // docs/browser-feature-research.md §3) — so both outcomes lead to
        // the same, reliable path below: export from Safari and choose that
        // file.
        _ = try? Data(contentsOf: BookmarkImportSourceDiscovery.safariBookmarksURL())
        stage = .safariGuidance
    }

    private var safariGuidanceStage: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Import from Safari")
                .font(.title2.bold())
            Text("macOS keeps Safari's bookmarks private to Safari. Limeghost cannot read them directly, and there is no setting that lets it ask automatically.")
                .font(.callout)
                .foregroundStyle(.secondary)
            Text("The reliable way in: open Safari, choose File ▸ Export ▸ Bookmarks…, then choose that file here.")
                .font(.callout)
            HStack(spacing: 10) {
                Button("Open Full Disk Access settings") {
                    NSWorkspace.shared.open(BookmarkImportSourceDiscovery.fullDiskAccessSettingsURL)
                }
                Button("Choose exported file…") { chooseFile(sourceLabelOverride: "Safari") }
                    .buttonStyle(.borderedProminent)
            }
            HStack {
                Button("Back") { stage = .chooseSource }
                Spacer()
                Button("Cancel") { finished(false) }
            }
        }
    }

    private func chooseFile(sourceLabelOverride: String?) {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.message = "Choose a bookmarks file exported from another browser."
        panel.prompt = "Import"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        loadAndPreview(
            from: url,
            sourceRowTitle: url.lastPathComponent,
            folderNamingLabel: sourceLabelOverride ?? "a file"
        )
    }

    // MARK: - Load + preview

    private func loadAndPreview(from url: URL, sourceRowTitle: String, folderNamingLabel: String) {
        switch BookmarkSourceLoader.load(from: url) {
        case .success(let loaded):
            let existing = BookmarkCollection(folders: store.bookmarkFolders, bookmarks: store.bookmarks)
            placement = BookmarkImportMergePlanner.recommendedPlacement(for: existing)
            stage = .preview(PreviewInfo(
                sourceRowTitle: sourceRowTitle,
                folderNamingLabel: folderNamingLabel,
                imported: loaded.imported,
                existing: existing,
                unusableCount: loaded.unusableCount
            ))
        case .failure(let message):
            stage = .problem(message)
        }
    }

    @ViewBuilder
    private func previewStage(_ info: PreviewInfo) -> some View {
        let plan = info.plan(placement)
        VStack(alignment: .leading, spacing: 16) {
            Text("Import from \(info.sourceRowTitle)")
                .font(.title2.bold())

            if plan.isEmpty {
                Text("Every bookmark Limeghost found here — \(Self.countedLabel(plan.sourceBookmarkCount, "bookmark")) in all — is already saved. There's nothing new to import.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    previewLine("Found", "\(Self.countedLabel(plan.sourceBookmarkCount, "bookmark")) in \(Self.countedLabel(plan.sourceFolderCount, "folder"))")
                    previewLine("Will be added", Self.countedLabel(plan.addedCount, "bookmark"))
                    if plan.skippedExistingCount > 0 {
                        previewLine("Already saved, left alone", Self.countedLabel(plan.skippedExistingCount, "bookmark"))
                    }
                    if plan.duplicateWithinImportCount > 0 {
                        previewLine("Repeated in the file", "\(Self.countedLabel(plan.duplicateWithinImportCount, "bookmark")), kept once")
                    }
                }

                placementChoice(info)

                Text(Self.placementExplanation(plan))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if !plan.barTitleCollisions.isEmpty {
                    Text(Self.collisionWarning(plan.barTitleCollisions))
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }

            HStack {
                Spacer()
                Button("Cancel") { finished(false) }
                if plan.isEmpty {
                    Button("Done") { finished(false) }
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut(.defaultAction)
                } else {
                    Button("Import") { performImport(info) }
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut(.defaultAction)
                }
            }
        }
    }

    /// The one decision worth asking about. Defaulted by what is already on
    /// the bar, but always shown, because somebody arriving from another
    /// browser and somebody topping up a bar they already arranged want
    /// opposite things and only they know which they are.
    @ViewBuilder
    private func placementChoice(_ info: PreviewInfo) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Where should these go?")
                .font(.callout)
                .foregroundStyle(.secondary)
            Picker("Where should these go?", selection: $placement) {
                Text("On my bookmarks bar").tag(BookmarkImportPlacement.bookmarksBar)
                Text("In one folder").tag(BookmarkImportPlacement.singleFolder)
            }
            .pickerStyle(.radioGroup)
            .labelsHidden()
            .accessibilityLabel("Where imported bookmarks should go")
        }
    }

    /// Says what will actually happen, per placement, and never promises
    /// more than the applier delivers.
    static func placementExplanation(_ plan: BookmarkImportPlan) -> String {
        let importFolderTitle = plan.importFolderIndex.map { plan.folders[$0].title }
        switch plan.placement {
        case .bookmarksBar:
            let barFolders = plan.folders.enumerated()
                .filter { $0.element.parentIndex == nil && $0.offset != plan.importFolderIndex }
                .count
            var text = barFolders == 1
                ? "One folder goes straight onto your bookmarks bar, next to what's already there"
                : "\(barFolders) folders go straight onto your bookmarks bar, next to what's already there"
            if let importFolderTitle {
                text += ", and anything this browser kept off its own bar goes into “\(importFolderTitle)”"
            }
            text += ". Nothing already saved is moved, renamed, or replaced."
            return text
        case .singleFolder:
            let name = importFolderTitle.map { "“\($0)”" } ?? "one new folder"
            return "Everything lands in \(name), organized the same way it already was. Nothing already saved is moved, renamed, or replaced."
        }
    }

    /// Named before the import runs, so two identically titled chips on the
    /// bar are a decision rather than a surprise.
    static func collisionWarning(_ titles: [String]) -> String {
        let quoted = titles.map { "“\($0)”" }
        let list: String
        switch quoted.count {
        case 1: list = quoted[0]
        case 2: list = "\(quoted[0]) and \(quoted[1])"
        default: list = quoted.dropLast().joined(separator: ", ") + ", and " + quoted[quoted.count - 1]
        }
        let verb = titles.count == 1 ? "a folder with that name" : "folders with those names"
        return "You already have \(verb) on your bar: \(list). Limeghost won't merge into \(titles.count == 1 ? "it" : "them") or rename anything, so you'll see both — yours untouched, and the imported one beside it."
    }

    /// Says where the bookmarks actually went, which under bar placement is
    /// two different places at once.
    static func resultHeadline(_ result: BookmarkImportApplyResult) -> String {
        let added = countedLabel(result.addedCount, "bookmark")
        switch result.placement {
        case .singleFolder:
            guard let title = result.importFolderTitle else { return "\(added) added." }
            return "\(added) added to “\(title)”."
        case .bookmarksBar:
            let folders = result.createdBarFolderCount
            let onBar = folders == 1 ? "1 folder" : "\(folders) folders"
            if let title = result.importFolderTitle, folders > 0 {
                return "\(added) added — \(onBar) on your bookmarks bar, and the rest in “\(title)”."
            }
            if let title = result.importFolderTitle {
                return "\(added) added to “\(title)”."
            }
            return "\(added) added — \(onBar) on your bookmarks bar."
        }
    }

    /// Deliberately not "nothing else is touched". Undo deletes the folders
    /// this import created, and a bookmark somebody moved into one of them
    /// afterwards is kept but reparented one level up. Saying so is cheap;
    /// discovering it is not.
    static func undoExplanation(_ result: BookmarkImportApplyResult) -> String {
        let bookmarks = countedLabel(result.addedCount, "bookmark")
        let created = result.createdFolderIDs.compactMap { $0 }.count
        let folders = created == 0 ? "" : "\(countedLabel(created, "folder")) and "
        return "Undo import removes the \(folders)\(bookmarks) this import added. If you've moved any of your own bookmarks into them since, those are kept and move up one level."
    }

    private func previewLine(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).foregroundStyle(.secondary)
            Spacer()
            Text(value).fontWeight(.medium)
        }
        .font(.callout)
    }

    // MARK: - Import + result

    private func performImport(_ info: PreviewInfo) {
        let result = BookmarkImportApplier.apply(info.plan(placement), into: store)
        stage = .result(result, unusableCount: info.unusableCount)
    }

    @ViewBuilder
    private func resultStage(_ result: BookmarkImportApplyResult, unusableCount: Int) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Import complete")
                .font(.title2.bold())
            VStack(alignment: .leading, spacing: 6) {
                Text(Self.resultHeadline(result))
                if result.skippedExistingCount > 0 {
                    Text("\(Self.countedLabel(result.skippedExistingCount, "address")) already saved — left exactly where they were.")
                }
                if result.duplicateWithinImportCount > 0 {
                    Text("\(Self.countedLabel(result.duplicateWithinImportCount, "bookmark")) repeated in the file — added once.")
                }
                if unusableCount > 0 {
                    Text("\(Self.countedLabel(unusableCount, "entry", plural: "entries")) couldn't be used.")
                }
            }
            .font(.callout)
            .foregroundStyle(.secondary)

            if !result.createdBookmarkIDs.isEmpty {
                Text(Self.undoExplanation(result))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack {
                if !result.createdBookmarkIDs.isEmpty {
                    Button("Undo import", role: .destructive) {
                        BookmarkImportApplier.undo(result, in: store)
                        finished(true)
                    }
                }
                Spacer()
                Button("Done") { finished(true) }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
        }
    }

    // MARK: - Problem

    private func problemStage(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Couldn't import that")
                .font(.title2.bold())
            Text(message)
                .font(.callout)
                .foregroundStyle(.secondary)
            HStack {
                Button("Back") { stage = .chooseSource }
                Spacer()
                Button("Cancel") { finished(false) }
            }
        }
    }

    // MARK: - Wording

    private static func countedLabel(_ count: Int, _ singular: String, plural: String? = nil) -> String {
        let word = count == 1 ? singular : (plural ?? "\(singular)s")
        return "\(count) \(word)"
    }
}
