import AppKit
import Combine
import Foundation
import LimeghostCore

/// What a new window shows when Limeghost starts.
///
/// Stored as the existing `clearframe.restoreTabs` boolean plus a page,
/// deliberately: that key is what `BrowserDataStore` already reads to decide
/// whether to write a session at all, and giving the choice a second home would
/// mean two sources of truth for one behaviour. This enum is a reading of that
/// key, not a replacement for it.
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
/// 2026, could not find: what opens at start, where Home goes, how big page
/// text is, and where downloaded files are saved.
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

    // MARK: - Start-up

    @Published var startup: StartupBehaviour {
        didSet {
            // `restoreTabs` stays authoritative for whether a session is
            // written at all, so it is set from here rather than shadowed.
            defaults.set(startup == .restore, forKey: Keys.restoreTabs)
            defaults.set(startup.rawValue, forKey: Keys.startup)
        }
    }

    @Published var startupPage: String {
        didSet { defaults.set(startupPage, forKey: Keys.startupPage) }
    }

    /// The address to open at start, or nil when the choice is not a specific
    /// page or the one stored is not a page Limeghost will open.
    var startupURL: URL? {
        guard startup == .specificPage else { return nil }
        return WebURLPolicy.validatedURL(startupPage)
    }

    private var startupURLWasTaken = false

    /// The start-up page, once per launch.
    ///
    /// The setting reads "when Limeghost opens", and a window built by ⌘N is
    /// not Limeghost opening. Without this the chosen page would reappear every
    /// time somebody made a window, which is a homepage — a different setting
    /// that this product does not have.
    func takeStartupURL() -> URL? {
        guard !startupURLWasTaken else { return nil }
        startupURLWasTaken = true
        return startupURL
    }

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

        // No stored choice means this is somebody who has used Limeghost
        // before the setting existed. Their `restoreTabs` answer is the choice
        // they already made, so it is read rather than overwritten.
        if let raw = defaults.string(forKey: Keys.startup),
           let stored = StartupBehaviour(rawValue: raw) {
            startup = stored
        } else {
            startup = defaults.bool(forKey: Keys.restoreTabs) ? .restore : .newTab
        }
        startupPage = defaults.string(forKey: Keys.startupPage) ?? ""

        homeTarget = defaults.string(forKey: Keys.homeTarget)
            .flatMap(HomeTarget.init(rawValue:)) ?? .aiGuide
        homePage = defaults.string(forKey: Keys.homePage) ?? ""

        let storedZoom = defaults.double(forKey: Keys.defaultPageZoom)
        defaultPageZoom = storedZoom > 0 ? CGFloat(storedZoom) : BrowserSession.defaultPageZoom

        downloadFolderPath = defaults.string(forKey: Keys.downloadFolder) ?? ""
        asksWhereToSave = defaults.object(forKey: Keys.askWhereToSave) as? Bool ?? true
    }

    private enum Keys {
        static let restoreTabs = "clearframe.restoreTabs"
        static let startup = "clearframe.startupBehaviour"
        static let startupPage = "clearframe.startupPage"
        static let homeTarget = "clearframe.homeTarget"
        static let homePage = "clearframe.homePage"
        static let defaultPageZoom = "clearframe.defaultPageZoom"
        static let downloadFolder = "clearframe.downloadFolder"
        static let askWhereToSave = "clearframe.askWhereToSave"
    }
}
