import ClearframeCore
import Combine
import Foundation

@MainActor
final class SearchSettingsStore: ObservableObject {
    static let initialDefault: SearchEngine = .duckDuckGo

    @Published var selectedEngine: SearchEngine {
        didSet { defaults.set(selectedEngine.rawValue, forKey: Keys.engine) }
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let rawValue = defaults.string(forKey: Keys.engine),
           let savedEngine = SearchEngine(rawValue: rawValue) {
            selectedEngine = savedEngine
        } else {
            selectedEngine = Self.initialDefault
        }
    }

    func searchURL(for query: String) -> URL? {
        selectedEngine.searchURL(for: query)
    }

    private enum Keys {
        static let engine = "clearframe.searchEngine"
    }
}
