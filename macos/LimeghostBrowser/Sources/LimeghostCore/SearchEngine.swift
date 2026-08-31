import Foundation

/// Web search endpoints supported by Limeghost's address bar.
///
/// These are ordinary public results URLs. Listing a provider does not imply a
/// partnership, endorsement, API integration, or revenue-sharing agreement.
public enum SearchEngine: String, CaseIterable, Codable, Identifiable, Sendable {
    case duckDuckGo
    case google
    case bing
    case braveSearch
    case startpage

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .duckDuckGo: return "DuckDuckGo"
        case .google: return "Google"
        case .bing: return "Bing"
        case .braveSearch: return "Brave Search"
        case .startpage: return "Startpage"
        }
    }

    public var resultsHost: String {
        switch self {
        case .duckDuckGo: return "duckduckgo.com"
        case .google: return "www.google.com"
        case .bing: return "www.bing.com"
        case .braveSearch: return "search.brave.com"
        case .startpage: return "www.startpage.com"
        }
    }

    public func searchURL(for rawQuery: String) -> URL? {
        let query = rawQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return nil }

        let path: String
        let queryName: String
        switch self {
        case .duckDuckGo:
            path = "/"
            queryName = "q"
        case .google, .bing, .braveSearch:
            path = "/search"
            queryName = "q"
        case .startpage:
            path = "/sp/search"
            queryName = "query"
        }

        guard let encodedQuery = Self.encodedQueryValue(query) else { return nil }
        var components = URLComponents()
        components.scheme = "https"
        components.host = resultsHost
        components.path = path
        // Not `queryItems`: it encodes with `urlQueryAllowed`, which leaves `+`
        // literal, and every engine listed here reads a literal `+` in a query
        // value as a space. A search for "C++ tutorial" would arrive as
        // "C tutorial". The value is encoded here instead, so the words the
        // user typed are the words the engine receives.
        components.percentEncodedQuery = "\(queryName)=\(encodedQuery)"
        return components.url
    }

    /// `urlQueryAllowed` permits the sub-delimiters a query string uses as
    /// syntax. Removing them keeps a typed `+`, `&`, or `=` part of the search
    /// text instead of turning it into a space or a second parameter.
    private static let queryValueAllowed: CharacterSet = {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "+&=?#;:@$,/")
        return allowed
    }()

    private static func encodedQueryValue(_ value: String) -> String? {
        value.addingPercentEncoding(withAllowedCharacters: queryValueAllowed)
    }
}
