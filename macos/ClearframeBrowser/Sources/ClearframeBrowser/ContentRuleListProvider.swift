import ClearframeCore
import Combine
import Foundation
@preconcurrency import WebKit

enum ContentBlockingStatus: Equatable {
    case compiling
    case active(ruleCount: Int)
    case disabled
    case unavailable(String)
}

/// Compiles the shipped tracker list into a `WKContentRuleList` and keeps every
/// live web view in sync with it.
///
/// WebKit applies the compiled rules inside the page process, so Clearframe can
/// report only what it applied — never what a page tried to load. `status` is
/// therefore the single honest source for the UI: it reaches `.active` only
/// after a list is genuinely compiled and attached.
@MainActor
final class ContentRuleListProvider: ObservableObject {
    @Published private(set) var status: ContentBlockingStatus = .compiling

    let settings: ContentBlockingSettingsStore
    let blockList: TrackerBlockList

    /// The identifier of the rule list currently attached to registered web
    /// views, or `nil` when nothing is attached.
    private(set) var appliedIdentifier: String?

    private let ruleStore: WKContentRuleListStore?
    private let thirdPartyOnly: Bool
    private let resourceTypes: [String]
    private let registeredWebViews = NSHashTable<WKWebView>.weakObjects()
    private var compiledList: WKContentRuleList?
    private var applyTask: Task<Void, Never>?
    private var settingsSubscription: AnyCancellable?

    init(
        settings: ContentBlockingSettingsStore,
        blockList: TrackerBlockList = TrackerBlockerCatalog.current,
        ruleStore: WKContentRuleListStore? = nil,
        thirdPartyOnly: Bool = true,
        resourceTypes: [String] = TrackerBlockerCatalog.resourceTypes
    ) {
        self.settings = settings
        self.blockList = blockList
        self.ruleStore = ruleStore ?? WKContentRuleListStore.default()
        self.thirdPartyOnly = thirdPartyOnly
        self.resourceTypes = resourceTypes
        settingsSubscription = settings.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }
        status = settings.isEnabled ? .compiling : .disabled
        apply()
    }

    var ruleCount: Int { Set(blockList.domains).count }

    var registeredWebViewCount: Int { registeredWebViews.count }

    /// Web views register once, at creation. The table holds them weakly so a
    /// closed tab does not keep its web view alive.
    func register(_ webView: WKWebView) {
        registeredWebViews.add(webView)
        attach(compiledList, to: webView)
    }

    func unregister(_ webView: WKWebView) {
        registeredWebViews.remove(webView)
        attach(nil, to: webView)
    }

    /// Completes only once the change has been applied to live web views, so
    /// callers can reload the page and see the new behaviour.
    func setEnabled(_ enabled: Bool) async {
        settings.setEnabled(enabled)
        await apply().value
    }

    func setSiteDisabled(_ disabled: Bool, forHost host: String) async {
        settings.setDisabled(disabled, forHost: host)
        await apply().value
    }

    func clearSiteExceptions() async {
        settings.clearExceptions()
        await apply().value
    }

    /// Awaits whatever compile is currently in flight, including the one
    /// started during initialisation.
    func refresh() async {
        await apply().value
    }

    @discardableResult
    private func apply() -> Task<Void, Never> {
        let previous = applyTask
        let task = Task { @MainActor [weak self] in
            _ = await previous?.value
            await self?.performApply()
        }
        applyTask = task
        return task
    }

    private func performApply() async {
        guard settings.isEnabled else {
            compiledList = nil
            appliedIdentifier = nil
            attachToRegisteredWebViews(nil)
            status = .disabled
            // A compiled list encodes the sites it was excluded from, so
            // nothing of it stays on disk once blocking is off.
            if let ruleStore { await removeStaleRuleLists(keeping: nil, in: ruleStore) }
            return
        }
        guard let ruleStore else {
            status = .unavailable("Clearframe could not open the local filter store.")
            return
        }

        let exceptions = settings.disabledHosts
        let identifier = Self.identifier(version: blockList.release.version, exceptionHosts: exceptions)
        if let compiledList, appliedIdentifier == identifier {
            attachToRegisteredWebViews(compiledList)
            status = .active(ruleCount: ruleCount)
            return
        }

        status = .compiling
        let source = ContentRuleListSource.make(
            domains: blockList.domains,
            resourceTypes: resourceTypes,
            thirdPartyOnly: thirdPartyOnly,
            exceptionHosts: exceptions
        )

        do {
            let list = try await loadOrCompile(identifier: identifier, source: source, in: ruleStore)
            compiledList = list
            appliedIdentifier = identifier
            attachToRegisteredWebViews(list)
            status = .active(ruleCount: ruleCount)
            await removeStaleRuleLists(keeping: identifier, in: ruleStore)
        } catch {
            compiledList = nil
            appliedIdentifier = nil
            attachToRegisteredWebViews(nil)
            status = .unavailable("Clearframe could not load the tracker filter.")
        }
    }

    /// Compiling ~200 rules is expensive, so a previously compiled list with the
    /// same identifier is reused. The identifier changes whenever the shipped
    /// list version or the set of per-site exceptions changes.
    private func loadOrCompile(
        identifier: String,
        source: String,
        in store: WKContentRuleListStore
    ) async throws -> WKContentRuleList {
        if let existing = try? await lookUp(identifier: identifier, in: store) { return existing }
        return try await withCheckedThrowingContinuation { continuation in
            store.compileContentRuleList(forIdentifier: identifier, encodedContentRuleList: source) { list, error in
                if let list {
                    continuation.resume(returning: list)
                } else {
                    continuation.resume(throwing: error ?? ContentBlockingError.compileFailed)
                }
            }
        }
    }

    private func lookUp(
        identifier: String,
        in store: WKContentRuleListStore
    ) async throws -> WKContentRuleList {
        try await withCheckedThrowingContinuation { continuation in
            store.lookUpContentRuleList(forIdentifier: identifier) { list, error in
                if let list {
                    continuation.resume(returning: list)
                } else {
                    continuation.resume(throwing: error ?? ContentBlockingError.missing)
                }
            }
        }
    }

    /// Old compiled lists would otherwise accumulate on disk after every list
    /// update or exception change.
    private func removeStaleRuleLists(keeping identifier: String?, in store: WKContentRuleListStore) async {
        let identifiers: [String] = await withCheckedContinuation { continuation in
            store.getAvailableContentRuleListIdentifiers { continuation.resume(returning: $0 ?? []) }
        }
        for stale in identifiers where stale.hasPrefix(Self.identifierPrefix) && stale != identifier {
            await withCheckedContinuation { continuation in
                store.removeContentRuleList(forIdentifier: stale) { _ in continuation.resume() }
            }
        }
    }

    private func attachToRegisteredWebViews(_ list: WKContentRuleList?) {
        for webView in registeredWebViews.allObjects {
            attach(list, to: webView)
        }
    }

    private func attach(_ list: WKContentRuleList?, to webView: WKWebView) {
        let controller = webView.configuration.userContentController
        controller.removeAllContentRuleLists()
        if let list { controller.add(list) }
    }

    static let identifierPrefix = "clearframe-tracker-block."

    static func identifier(version: String, exceptionHosts: [String]) -> String {
        let exceptions = Set(exceptionHosts).sorted().joined(separator: ",")
        return "\(identifierPrefix)v\(version).x\(StableHash.fnv1a64Hex(exceptions))"
    }
}

enum ContentBlockingError: Error {
    case missing
    case compileFailed
}
