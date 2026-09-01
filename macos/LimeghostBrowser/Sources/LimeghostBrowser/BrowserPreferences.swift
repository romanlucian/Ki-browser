import AppKit
import Combine
import Foundation
import LimeghostCore

/// What a window shows when Limeghost starts. Stored per profile on
/// `BrowserDataStore`, beside the `restoreTabs` key it writes.
enum StartupBehaviour: String, CaseIterable, Identifiable {
    case newTab
    case restore
    case specificPage

    var id: String { rawValue }

    var title: String {
        switch self {
        case .newTab: return "The AI guide"
        case .restore: return "The tabs I had open"
        case .specificPage: return "A specific page"
        }
    }
}

/// What the Home button and ⌘⇧H return a tab to.
enum HomeTarget: String, CaseIterable, Identifiable {
    case aiGuide
    case bookmarks
    case specificPage

    var id: String { rawValue }

    var title: String {
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
final class BrowserPreferences: ObservableObject {
    static let shared = BrowserPreferences()

    private let defaults: UserDefaults

    // MARK: - Home

    @Published var homeTarget: HomeTarget {
        didSet { defaults.set(homeTarget.rawValue, forKey: Keys.homeTarget) }
    }

    @Published var homePage: String {
        didSet { defaults.set(homePage, forKey: Keys.homePage) }
    }

    var homeURL: URL? {
        guard homeTarget == .specificPage else { return nil }
        return WebURLPolicy.validatedURL(homePage)
    }

    // MARK: - Pages

    /// The zoom every new tab starts at. One of `BrowserSession.pageZoomSteps`,
    /// so the setting and ⌘+/⌘− speak in the same increments.
    @Published var defaultPageZoom: CGFloat {
        didSet { defaults.set(Double(defaultPageZoom), forKey: Keys.defaultPageZoom) }
    }

    // MARK: - Downloads

    /// Where files go when Limeghost is not asking. Empty means the Mac's own
    /// Downloads folder.
    @Published var downloadFolderPath: String {
        didSet { defaults.set(downloadFolderPath, forKey: Keys.downloadFolder) }
    }

    /// On by default, because that is what Limeghost has always done and a
    /// download that silently lands somewhere is worse than one that asks.
    @Published var asksWhereToSave: Bool {
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
    var resolvedDownloadFolder: URL? {
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
    var downloadFolderDisplayName: String {
        if downloadFolderPath.isEmpty {
            return FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)
                .first?.lastPathComponent ?? "Downloads"
        }
        return URL(fileURLWithPath: downloadFolderPath).lastPathComponent
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        homeTarget = defaults.string(forKey: Keys.homeTarget)
            .flatMap(HomeTarget.init(rawValue:)) ?? .aiGuide
        homePage = defaults.string(forKey: Keys.homePage) ?? ""

        let storedZoom = defaults.double(forKey: Keys.defaultPageZoom)
        defaultPageZoom = storedZoom > 0 ? CGFloat(storedZoom) : BrowserSession.defaultPageZoom

        downloadFolderPath = defaults.string(forKey: Keys.downloadFolder) ?? ""
        asksWhereToSave = defaults.object(forKey: Keys.askWhereToSave) as? Bool ?? true
    }

    private enum Keys {
        static let homeTarget = "clearframe.homeTarget"
        static let homePage = "clearframe.homePage"
        static let defaultPageZoom = "clearframe.defaultPageZoom"
        static let downloadFolder = "clearframe.downloadFolder"
        static let askWhereToSave = "clearframe.askWhereToSave"
    }
}
