import LimeghostCore
import Combine
import Foundation
@preconcurrency import WebKit

/// Plain words for the kinds of data a website leaves behind on this Mac.
///
/// WebKit hands back exactly two facts per site: a display name and the set of
/// `WKWebsiteDataType` values it holds. There is no byte size and no cookie
/// count anywhere in that API, so this vocabulary is the whole of what
/// Limeghost can honestly say about a site's storage. Kept as a mapping over
/// plain strings — the same shape `ShieldState` uses — so it can be tested on
/// its own without a web view.
enum SiteDataKind: String, CaseIterable, Comparable {
    case cookies
    case cachedFiles
    case localStorage
    case databases
    case serviceWorkers
    case storedFiles
    case mediaKeys
    case recentSearches
    case deviceIdentifiers
    case screenTime
    /// A `WKWebsiteDataType` this build does not have words for — a newer macOS
    /// can add one at any time. Named rather than dropped, because a site that
    /// stored something the app cannot name still stored something.
    case other

    /// Lowercase because these read as items in a sentence-case list.
    var label: String {
        switch self {
        case .cookies: return "cookies"
        case .cachedFiles: return "cached files"
        case .localStorage: return "local storage"
        case .databases: return "databases"
        case .serviceWorkers: return "background service workers"
        case .storedFiles: return "stored files"
        case .mediaKeys: return "media playback keys"
        case .recentSearches: return "recent searches in page search fields"
        case .deviceIdentifiers: return "media device identifiers"
        case .screenTime: return "Screen Time records"
        case .other: return "other site data"
        }
    }

    /// Display order: what people recognize first, then the machinery, then the
    /// catch-all.
    private var rank: Int {
        switch self {
        case .cookies: return 0
        case .cachedFiles: return 1
        case .localStorage: return 2
        case .databases: return 3
        case .serviceWorkers: return 4
        case .storedFiles: return 5
        case .mediaKeys: return 6
        case .recentSearches: return 7
        case .deviceIdentifiers: return 8
        case .screenTime: return 9
        case .other: return 10
        }
    }

    static func < (lhs: SiteDataKind, rhs: SiteDataKind) -> Bool {
        lhs.rank < rhs.rank
    }

    /// Groups WebKit's constants into words an ordinary reader can act on.
    /// Several WebKit types describe the same everyday thing — three separate
    /// caches are still "cached files" — so the mapping deliberately collapses
    /// them rather than listing engine internals.
    static func kind(forDataType rawValue: String) -> SiteDataKind {
        switch rawValue {
        case WKWebsiteDataTypeCookies:
            return .cookies
        case WKWebsiteDataTypeDiskCache,
             WKWebsiteDataTypeMemoryCache,
             WKWebsiteDataTypeFetchCache,
             WKWebsiteDataTypeOfflineWebApplicationCache:
            return .cachedFiles
        case WKWebsiteDataTypeLocalStorage,
             WKWebsiteDataTypeSessionStorage:
            return .localStorage
        case WKWebsiteDataTypeIndexedDBDatabases,
             WKWebsiteDataTypeWebSQLDatabases:
            return .databases
        case WKWebsiteDataTypeServiceWorkerRegistrations:
            return .serviceWorkers
        case WKWebsiteDataTypeFileSystem:
            return .storedFiles
        case WKWebsiteDataTypeMediaKeys:
            return .mediaKeys
        case WKWebsiteDataTypeSearchFieldRecentSearches:
            return .recentSearches
        case WKWebsiteDataTypeHashSalt:
            return .deviceIdentifiers
        // Spelled out rather than referenced: WebKit's symbol for this one is
        // marked available only on much newer macOS than Limeghost's
        // deployment target, while the store on a Mac that has it does return
        // this exact value. Its raw value is its own name, like every other
        // `WKWebsiteDataType`.
        case "WKWebsiteDataTypeScreenTime":
            return .screenTime
        default:
            return .other
        }
    }

    /// Deduplicated and ordered, so a site holding three kinds of cache reads
    /// as "cached files" once.
    static func kinds(for dataTypes: Set<String>) -> [SiteDataKind] {
        Set(dataTypes.map(kind(forDataType:))).sorted()
    }

    /// One sentence-case line naming what a site holds. Never a size, never a
    /// count — WebKit reports neither.
    static func summary(of kinds: [SiteDataKind]) -> String {
        guard let first = kinds.first else { return "Site data" }
        // Spelled out with explicit String conversions: `prefix(1)` on a String
        // is ambiguous enough that older Swift resolves it to the Sequence
        // overload, which has no `uppercased()`. It built here and failed on CI.
        let head = String(first.label.prefix(1)).uppercased()
        let tail = String(first.label.dropFirst())
        let rest = kinds.dropFirst().map(\.label)
        return ([head + tail] + rest).joined(separator: ", ")
    }
}

/// One site that currently holds data in the default (non-private) website
/// data store.
struct SiteDataEntry: Identifiable, Equatable {
    /// WebKit's own display name for the site — usually the registrable domain,
    /// so `www.example.com` and `shop.example.com` share one entry.
    let displayName: String
    let kinds: [SiteDataKind]

    var id: String { displayName }
    var kindSummary: String { SiteDataKind.summary(of: kinds) }
}

/// Reads and removes per-site website data.
///
/// Only `WKWebsiteDataStore.default()` is consulted: private tabs run on
/// non-persistent stores, so nothing they touched is ever listed here or left
/// behind for this type to remove.
@MainActor
final class SiteDataInventory: ObservableObject {
    enum LoadState: Equatable {
        case idle
        case loading
        case loaded
    }

    @Published private(set) var state: LoadState = .idle
    @Published private(set) var sites: [SiteDataEntry] = []
    /// The site a removal is currently running for, so its row can say so
    /// instead of appearing to do nothing.
    @Published private(set) var removingSite: String?

    private let dataStore: WKWebsiteDataStore

    /// Defaults to the shared persistent store. Resolved inside the initializer
    /// rather than in the parameter list because `WKWebsiteDataStore.default()`
    /// is main-actor isolated and a default argument is evaluated outside that
    /// isolation.
    init(dataStore: WKWebsiteDataStore? = nil) {
        self.dataStore = dataStore ?? .default()
    }

    var isEmpty: Bool { state == .loaded && sites.isEmpty }

    func refresh() async {
        // Only the first read announces itself. A re-read after a removal keeps
        // the list on screen rather than emptying it and building it again,
        // which reads as the whole list having been deleted.
        if state == .idle { state = .loading }
        sites = Self.entries(from: await fetchRecords())
        state = .loaded
    }

    /// The kinds one host holds, without disturbing the full listing. Used by
    /// the address-bar site information popover.
    func kinds(forHost host: String) async -> [SiteDataKind] {
        let matching = await fetchRecords().filter { Self.matches(displayName: $0.displayName, host: host) }
        return SiteDataKind.kinds(for: Set(matching.flatMap(\.dataTypes)))
    }

    func remove(_ entry: SiteDataEntry) async {
        let records = await fetchRecords().filter { $0.displayName == entry.displayName }
        guard !records.isEmpty else {
            await refresh()
            return
        }
        removingSite = entry.displayName
        await remove(records: records)
        removingSite = nil
        await refresh()
    }

    /// Removes everything the default store holds for one host, including the
    /// records WebKit groups under the site's registrable domain. Returns
    /// `false` when the host held nothing, so a caller can say so plainly.
    @discardableResult
    func remove(forHost host: String) async -> Bool {
        let records = await fetchRecords().filter { Self.matches(displayName: $0.displayName, host: host) }
        guard !records.isEmpty else { return false }
        removingSite = host
        await remove(records: records)
        removingSite = nil
        if state != .idle { await refresh() }
        return true
    }

    /// Whether a WebKit record's display name covers a page's host. WebKit
    /// reports the registrable domain, so `www.example.com` and
    /// `shop.example.com` both belong to the `example.com` record; matching on
    /// equality alone would silently fail to remove a subdomain's data.
    static func matches(displayName: String, host: String) -> Bool {
        let name = displayName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let host = host.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !name.isEmpty, !host.isEmpty else { return false }
        if name == host { return true }
        return host.hasSuffix(".\(name)") || name.hasSuffix(".\(host)")
    }

    /// Sorted the way a person reads a list of sites, with records sharing a
    /// display name folded into one row.
    static func entries(from records: [WKWebsiteDataRecord]) -> [SiteDataEntry] {
        var byName: [String: Set<String>] = [:]
        for record in records {
            let name = record.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { continue }
            byName[name, default: []].formUnion(record.dataTypes)
        }
        return byName
            .map { SiteDataEntry(displayName: $0.key, kinds: SiteDataKind.kinds(for: $0.value)) }
            .sorted { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending }
    }

    private func fetchRecords() async -> [WKWebsiteDataRecord] {
        await withCheckedContinuation { continuation in
            dataStore.fetchDataRecords(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes()) { records in
                continuation.resume(returning: records)
            }
        }
    }

    private func remove(records: [WKWebsiteDataRecord]) async {
        await withCheckedContinuation { continuation in
            dataStore.removeData(
                ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(),
                for: records
            ) {
                continuation.resume()
            }
        }
    }
}
