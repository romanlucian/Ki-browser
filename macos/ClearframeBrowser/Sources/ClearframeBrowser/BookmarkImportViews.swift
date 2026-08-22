import AppKit
import ClearframeCore
import SwiftUI

/// What actually happened when a `BookmarkImportPlan` was applied to the
/// store: the real folder and bookmark ids it created, in the order it
/// created them. Carrying the ids (not just counts) is what makes `undo`
/// possible — and what makes the sheet's promise that removing the
/// destination folder undoes the whole import actually true.
struct BookmarkImportApplyResult: Equatable {
    /// `nil` when the plan was empty and nothing — not even the destination
    /// folder — was created.
    let destinationFolderID: UUID?
    let destinationFolderTitle: String
    /// Parent-before-child: the same order `BookmarkImportPlan.folders`
    /// listed them in, which is the order they were created in.
    let createdFolderIDs: [UUID]
    let createdBookmarkIDs: [UUID]
    let skippedExistingCount: Int
    let duplicateWithinImportCount: Int

    var addedCount: Int { createdBookmarkIDs.count }
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
    static func apply(
        _ plan: BookmarkImportPlan,
        destinationFolderTitle: String,
        into store: BrowserDataStore
    ) -> BookmarkImportApplyResult {
        // The single most important rule this whole feature exists to
        // protect: an address already saved is skipped, never re-added, so
        // `BookmarkCollection.addBookmark`'s replace-on-matching-URL
        // behavior never has a chance to move or rename an existing
        // bookmark. `plan` already excludes every such address — this
        // function only ever creates brand-new records.
        guard !plan.isEmpty else {
            return emptyResult(destinationFolderTitle: destinationFolderTitle, plan: plan)
        }

        guard let destination = store.createBookmarkFolder(
            title: destinationFolderTitle,
            iconID: ClearframeIconCatalog.defaultIconID,
            colorID: nil,
            parentID: nil
        ) else {
            // Only a blank title can make folder creation refuse, and a
            // formatted "Imported from X — date" title never is one.
            return emptyResult(destinationFolderTitle: destinationFolderTitle, plan: plan)
        }

        var createdFolderIDs: [UUID] = []
        for planned in plan.folders {
            let parentID = planned.parentIndex.map { createdFolderIDs[$0] } ?? destination.id
            let created = store.createBookmarkFolder(
                title: planned.title,
                iconID: ClearframeIconCatalog.defaultIconID,
                colorID: nil,
                parentID: parentID
            )
            createdFolderIDs.append(created?.id ?? parentID)
        }

        var createdBookmarkIDs: [UUID] = []
        for planned in plan.bookmarks {
            let parentID = planned.parentIndex.map { createdFolderIDs[$0] } ?? destination.id
            if let created = store.addBookmark(title: planned.title, url: planned.url, folderID: parentID) {
                createdBookmarkIDs.append(created.id)
            }
        }

        return BookmarkImportApplyResult(
            destinationFolderID: destination.id,
            destinationFolderTitle: destinationFolderTitle,
            createdFolderIDs: createdFolderIDs,
            createdBookmarkIDs: createdBookmarkIDs,
            skippedExistingCount: plan.skippedExistingCount,
            duplicateWithinImportCount: plan.duplicateWithinImportCount
        )
    }

    private static func emptyResult(destinationFolderTitle: String, plan: BookmarkImportPlan) -> BookmarkImportApplyResult {
        BookmarkImportApplyResult(
            destinationFolderID: nil,
            destinationFolderTitle: destinationFolderTitle,
            createdFolderIDs: [],
            createdBookmarkIDs: [],
            skippedExistingCount: plan.skippedExistingCount,
            duplicateWithinImportCount: plan.duplicateWithinImportCount
        )
    }

    /// Removes every bookmark this import created, then deletes every folder
    /// it created, deepest first, and finally the destination folder itself.
    /// By the time any one folder's turn comes, its own bookmarks are
    /// already gone and every subfolder has already been removed, so it is
    /// genuinely empty — the existing preserve-contents delete has nothing
    /// left to preserve and simply removes it, the same way it already does
    /// for any other empty folder. Nothing this import did not create is
    /// ever touched.
    static func undo(_ result: BookmarkImportApplyResult, in store: BrowserDataStore) {
        for bookmarkID in result.createdBookmarkIDs {
            guard let bookmark = store.bookmarks.first(where: { $0.id == bookmarkID }) else { continue }
            store.removeBookmark(bookmark)
        }
        for folderID in result.createdFolderIDs.reversed() {
            guard let folder = store.bookmarkFolder(id: folderID) else { continue }
            store.deleteBookmarkFolderPreservingContents(folder)
        }
        if let destinationID = result.destinationFolderID, let destination = store.bookmarkFolder(id: destinationID) {
            store.deleteBookmarkFolderPreservingContents(destination)
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

    private enum Stage {
        case chooseSource
        case safariGuidance
        case preview(PreviewInfo)
        case result(BookmarkImportApplyResult, unusableCount: Int)
        case problem(String)
    }

    private struct PreviewInfo {
        let sourceRowTitle: String
        let folderNamingLabel: String
        let plan: BookmarkImportPlan
        let unusableCount: Int
        var destinationFolderTitle: String {
            BookmarkImportFolderNaming.destinationFolderTitle(sourceLabel: folderNamingLabel)
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
        // Clearframe does not parse the plist — its schema is recalled from
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
            Text("macOS keeps Safari's bookmarks private to Safari. Clearframe cannot read them directly, and there is no setting that lets it ask automatically.")
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
            let plan = BookmarkImportMergePlanner.plan(loaded.imported, into: existing)
            stage = .preview(PreviewInfo(
                sourceRowTitle: sourceRowTitle,
                folderNamingLabel: folderNamingLabel,
                plan: plan,
                unusableCount: loaded.unusableCount
            ))
        case .failure(let message):
            stage = .problem(message)
        }
    }

    @ViewBuilder
    private func previewStage(_ info: PreviewInfo) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Import from \(info.sourceRowTitle)")
                .font(.title2.bold())

            if info.plan.isEmpty {
                Text("Every bookmark Clearframe found here — \(Self.countedLabel(info.plan.sourceBookmarkCount, "bookmark")) in all — is already saved. There's nothing new to import.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    previewLine("Found", "\(Self.countedLabel(info.plan.sourceBookmarkCount, "bookmark")) in \(Self.countedLabel(info.plan.sourceFolderCount, "folder"))")
                    previewLine("Will be added", Self.countedLabel(info.plan.addedCount, "bookmark"))
                    if info.plan.skippedExistingCount > 0 {
                        previewLine("Already saved, left alone", Self.countedLabel(info.plan.skippedExistingCount, "bookmark"))
                    }
                    if info.plan.duplicateWithinImportCount > 0 {
                        previewLine("Repeated in the file", "\(Self.countedLabel(info.plan.duplicateWithinImportCount, "bookmark")), kept once")
                    }
                    previewLine("Destination", "“\(info.destinationFolderTitle)”")
                }
                Text("Everything lands in that one new folder, organized the same way it already was. Nothing already saved is moved, renamed, or replaced. If you change your mind, choose Undo import on the next screen to remove that folder and everything in it — nothing else is touched.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack {
                Spacer()
                Button("Cancel") { finished(false) }
                if info.plan.isEmpty {
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
        let result = BookmarkImportApplier.apply(
            info.plan,
            destinationFolderTitle: info.destinationFolderTitle,
            into: store
        )
        stage = .result(result, unusableCount: info.unusableCount)
    }

    @ViewBuilder
    private func resultStage(_ result: BookmarkImportApplyResult, unusableCount: Int) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Import complete")
                .font(.title2.bold())
            VStack(alignment: .leading, spacing: 6) {
                Text("\(Self.countedLabel(result.addedCount, "bookmark")) added to “\(result.destinationFolderTitle)”.")
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

            if result.destinationFolderID != nil {
                Text("Undo import removes “\(result.destinationFolderTitle)” and everything in it. Nothing else is touched.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack {
                if result.destinationFolderID != nil {
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
