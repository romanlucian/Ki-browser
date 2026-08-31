import LimeghostCore
import Foundation
import WebKit

/// The list of profiles, and which one new windows open in.
///
/// The list itself lives in the app's own preferences rather than in any
/// profile: it has to be readable before a profile has been chosen.
@MainActor
final class ProfileStore: ObservableObject {
    @Published private(set) var profiles: [BrowserProfileRecord]
    /// The profile a new window opens in. A window keeps the profile it was
    /// opened with for as long as it lives; changing this only affects
    /// windows opened afterwards.
    @Published private(set) var currentProfileID: UUID

    private let defaults: UserDefaults
    private enum Keys {
        static let profiles = "clearframe.profiles.v1"
        static let current = "clearframe.profiles.current"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let stored = Self.load(from: defaults)
        // There is always at least the original profile. Someone upgrading
        // finds their existing bookmarks, history and logins in it, because it
        // is the one that keeps the app's original stores.
        let resolved = stored.isEmpty ? [Self.originalProfile] : stored
        let savedCurrent = defaults.string(forKey: Keys.current).flatMap(UUID.init(uuidString:))
        profiles = resolved
        currentProfileID = resolved.first { $0.id == savedCurrent }?.id ?? resolved[0].id
    }

    static var originalProfile: BrowserProfileRecord {
        BrowserProfileRecord(
            id: BrowserProfileRecord.defaultID,
            name: "Personal",
            colorID: TabGroupRecord.colorIDs[1]
        )
    }

    func profile(_ id: UUID) -> BrowserProfileRecord? {
        profiles.first { $0.id == id }
    }

    var currentProfile: BrowserProfileRecord {
        profile(currentProfileID) ?? profiles[0]
    }

    func setCurrent(_ id: UUID) {
        guard profiles.contains(where: { $0.id == id }) else { return }
        currentProfileID = id
        defaults.set(id.uuidString, forKey: Keys.current)
    }

    @discardableResult
    func addProfile(name: String, colorID: String? = nil) -> BrowserProfileRecord {
        let record = BrowserProfileRecord(
            name: BrowserProfileRecord.sanitizedName(name),
            colorID: colorID ?? nextColorID()
        )
        profiles.append(record)
        save()
        return record
    }

    func rename(_ id: UUID, to name: String) {
        guard let index = profiles.firstIndex(where: { $0.id == id }) else { return }
        profiles[index].name = BrowserProfileRecord.sanitizedName(name, fallback: profiles[index].name)
        save()
    }

    func recolor(_ id: UUID, to colorID: String) {
        guard let index = profiles.firstIndex(where: { $0.id == id }),
              TabGroupRecord.colorIDs.contains(colorID) else { return }
        profiles[index].colorID = colorID
        save()
    }

    /// Whether a profile can be removed. The original one cannot: it holds the
    /// data that existed before profiles did, and there has to be somewhere
    /// for a window to open.
    func canDelete(_ id: UUID) -> Bool {
        id != BrowserProfileRecord.defaultID && profiles.count > 1
    }

    /// Forgets a profile and everything behind it — its bookmarks, history,
    /// saved session, site icons, per-site exceptions, and the logins in its
    /// WebKit store. There is no undo, so the caller asks first.
    func deleteProfile(_ id: UUID) {
        guard canDelete(id) else { return }
        profiles.removeAll { $0.id == id }
        if currentProfileID == id { setCurrent(profiles[0].id) }
        save()
        ProfileStorage.erase(profileID: id)
    }

    private func nextColorID() -> String {
        let used = Set(profiles.map(\.colorID))
        return TabGroupRecord.colorIDs.first { !used.contains($0) } ?? TabGroupRecord.colorIDs[0]
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(profiles) else { return }
        defaults.set(data, forKey: Keys.profiles)
    }

    private static func load(from defaults: UserDefaults) -> [BrowserProfileRecord] {
        guard let data = defaults.data(forKey: Keys.profiles),
              let decoded = try? JSONDecoder().decode([BrowserProfileRecord].self, from: data)
        else { return [] }
        return decoded
    }
}

/// Where a profile's data actually sits.
///
/// The original profile deliberately keeps the app's first locations, so
/// upgrading does not strand anybody's bookmarks, history or logins behind a
/// new identifier. Every other profile gets its own preferences suite, its own
/// icon folder, and its own WebKit data store, which is what keeps two
/// profiles signed into the same site apart.
enum ProfileStorage {
    static func defaults(for profileID: UUID) -> UserDefaults {
        guard profileID != BrowserProfileRecord.defaultID else { return .standard }
        return UserDefaults(suiteName: suiteName(for: profileID)) ?? .standard
    }

    static func suiteName(for profileID: UUID) -> String {
        "com.clearframe.browser.profile.\(profileID.uuidString)"
    }

    static func faviconDirectory(for profileID: UUID) -> URL? {
        guard profileID != BrowserProfileRecord.defaultID else { return FaviconStore.defaultDirectory }
        return FaviconStore.defaultDirectory?
            .deletingLastPathComponent()
            .appendingPathComponent("Profiles/\(profileID.uuidString)/SiteIcons", isDirectory: true)
    }

    /// The WebKit store holding this profile's cookies and logins. The
    /// original profile uses the default store, which is where anything saved
    /// before profiles existed already is.
    static func websiteDataStore(for profileID: UUID) -> WKWebsiteDataStore {
        guard profileID != BrowserProfileRecord.defaultID else { return .default() }
        return WKWebsiteDataStore(forIdentifier: profileID)
    }

    /// Removes everything a deleted profile owned.
    static func erase(profileID: UUID) {
        guard profileID != BrowserProfileRecord.defaultID else { return }
        let suite = suiteName(for: profileID)
        UserDefaults.standard.removePersistentDomain(forName: suite)
        // Emptying the domain leaves the file it lived in behind, named after
        // the profile. A deleted profile should not leave its name on disk,
        // so the file goes too.
        if let library = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first {
            try? FileManager.default.removeItem(
                at: library.appendingPathComponent("Preferences/\(suite).plist")
            )
        }
        if let directory = faviconDirectory(for: profileID) {
            try? FileManager.default.removeItem(at: directory)
        }
        WKWebsiteDataStore.remove(forIdentifier: profileID) { _ in }
    }
}
