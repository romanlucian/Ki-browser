import Combine
import Foundation
import LimeghostCore

/// What a window shows when Limeghost starts. Stored per profile on
/// `BrowserDataStore`, beside the `restoreTabs` key it writes.
public enum StartupBehaviour: String, CaseIterable, Identifiable {
    case newTab
    case restore
    case specificPage

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .newTab: return "The AI guide"
        case .restore: return "The tabs I had open"
        case .specificPage: return "A specific page"
        }
    }
}

/// What the Home button and ⌘⇧H return a tab to.
public enum HomeTarget: String, CaseIterable, Identifiable {
    case aiGuide
    case bookmarks
    case specificPage

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .aiGuide: return "The AI guide"
        case .bookmarks: return "Bookmarks"
        case .specificPage: return "A specific page"
        }
    }
}

/// The preferences an ordinary person goes looking for and, until September 1,
/// 2026, could not find: where Home goes, how big page text is, and where
/// downloaded files are saved.
///
/// Application-wide, in the standard suite. What opens at start deliberately
/// is **not** here: it decides whether a session is written, which is a
/// per-profile question, so it lives on `BrowserDataStore` beside the profile's
/// own `restoreTabs`. A copy here would be invisible to every profile but the
/// default one.
///
/// One store rather than scattered `@AppStorage`, because several of these are
/// read from outside a view — `BrowserTab.goHome`, `DownloadCenter`, and every
/// new session's zoom — and a property wrapper only works where a view is.
///
/// Every key keeps the `clearframe.` prefix. The storage names were left behind
/// deliberately at the rename and must not be tidied; see CLAUDE.md.
@MainActor
public final class BrowserPreferences: ObservableObject {
    public static let shared = BrowserPreferences()

    private let defaults: UserDefaults

    // MARK: - Home

    @Published public var homeTarget: HomeTarget {
        didSet { defaults.set(homeTarget.rawValue, forKey: Keys.homeTarget) }
    }

    @Published public var homePage: String {
        didSet { defaults.set(homePage, forKey: Keys.homePage) }
    }

    public var homeURL: URL? {
        guard homeTarget == .specificPage else { return nil }
        return WebURLPolicy.validatedURL(homePage)
    }

    // MARK: - Pages

    /// The zoom every new tab starts at. One of `BrowserSession.pageZoomSteps`,
    /// so the setting and ⌘+/⌘− speak in the same increments.
    @Published public var defaultPageZoom: CGFloat {
        didSet { defaults.set(Double(defaultPageZoom), forKey: Keys.defaultPageZoom) }
    }

    // MARK: - Downloads

    /// Where files go when Limeghost is not asking. Empty means the Mac's own
    /// Downloads folder.
    @Published public var downloadFolderPath: String {
        didSet { defaults.set(downloadFolderPath, forKey: Keys.downloadFolder) }
    }

    /// On by default, because that is what Limeghost has always done and a
    /// download that silently lands somewhere is worse than one that asks.
    @Published public var asksWhereToSave: Bool {
        didSet { defaults.set(asksWhereToSave, forKey: Keys.askWhereToSave) }
    }

    /// The folder to write into, or nil when Limeghost should show the save
    /// panel instead.
    ///
    /// Returns nil for a folder that is gone or not writable rather than
    /// handing `WKDownload` a destination it will fail on: the app is not
    /// sandboxed, so a folder can be readable in the picker and refused later
    /// by the privacy system. Falling back to the panel is visible; a failed
    /// download that says only "failed" is not.
    public var resolvedDownloadFolder: URL? {
        guard !asksWhereToSave else { return nil }
        let folder = downloadFolderPath.isEmpty
            ? FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
            : URL(fileURLWithPath: downloadFolderPath)
        guard let folder else { return nil }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: folder.path, isDirectory: &isDirectory),
              isDirectory.boolValue,
              FileManager.default.isWritableFile(atPath: folder.path) else { return nil }
        return folder
    }

    /// What the Downloads settings row shows for the chosen folder.
    public var downloadFolderDisplayName: String {
        if downloadFolderPath.isEmpty {
            return FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)
                .first?.lastPathComponent ?? "Downloads"
        }
        return URL(fileURLWithPath: downloadFolderPath).lastPathComponent
    }

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        homeTarget = defaults.string(forKey: Keys.homeTarget)
            .flatMap(HomeTarget.init(rawValue:)) ?? .aiGuide
        homePage = defaults.string(forKey: Keys.homePage) ?? ""

        let storedZoom = defaults.double(forKey: Keys.defaultPageZoom)
        defaultPageZoom = storedZoom > 0 ? CGFloat(storedZoom) : Self.unzoomedPageZoom

        downloadFolderPath = defaults.string(forKey: Keys.downloadFolder) ?? ""
        asksWhereToSave = defaults.object(forKey: Keys.askWhereToSave) as? Bool ?? true
    }

    /// The unzoomed page value — 1.0, identical to `BrowserSession.defaultPageZoom`.
    /// Duplicated rather than referenced: `BrowserSession` has not moved into this
    /// target yet (Task 7 moves it, alongside `AICompanion`), and this target
    /// cannot depend back on the app target to read its constant. Reunify the two
    /// once `BrowserSession` is here too.
    private static let unzoomedPageZoom: CGFloat = 1.0

    private enum Keys {
        static let homeTarget = "clearframe.homeTarget"
        static let homePage = "clearframe.homePage"
        static let defaultPageZoom = "clearframe.defaultPageZoom"
        static let downloadFolder = "clearframe.downloadFolder"
        static let askWhereToSave = "clearframe.askWhereToSave"
    }
}
