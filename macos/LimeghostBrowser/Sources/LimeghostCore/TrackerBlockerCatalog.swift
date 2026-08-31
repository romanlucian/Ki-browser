import Foundation

public struct TrackerBlockListRelease: Equatable, Sendable {
    public let version: String
    public let lastChecked: Date

    public init(version: String, lastChecked: Date) {
        self.version = version
        self.lastChecked = lastChecked
    }
}

public struct TrackerBlockList: Equatable, Sendable {
    public let release: TrackerBlockListRelease
    public let domains: [String]

    public init(release: TrackerBlockListRelease, domains: [String]) {
        self.release = release
        self.domains = domains
    }
}

public enum TrackerBlockerCatalog {
    /// A small, first-party editorial list shipped with the app. Like the AI
    /// catalog it carries a visible version and checked date; it is never
    /// fetched or replaced at runtime, and it is not derived from EasyList or
    /// any other third-party blocklist.
    public static let release = TrackerBlockListRelease(
        version: "2026.08.14.1",
        lastChecked: Calendar(identifier: .gregorian).date(
            from: DateComponents(timeZone: TimeZone(secondsFromGMT: 0), year: 2026, month: 8, day: 14)
        )!
    )

    /// Request kinds a tracking domain typically uses. `document` covers
    /// third-party frames; top-level navigation to a listed domain stays
    /// first-party and therefore keeps working.
    public static let resourceTypes: [String] = [
        "script",
        "image",
        "style-sheet",
        "font",
        "media",
        "raw",
        "popup",
        "document"
    ]

    public static let current = TrackerBlockList(
        release: release,
        domains: TrackerBlockerCatalogData.domains
    )
}

public enum ContentRuleListSource {
    /// Emits WebKit content-rule JSON for a domain list. The output is
    /// deterministic (sorted, deduplicated, fixed key order) so an identical
    /// configuration reuses the already compiled rule list instead of paying
    /// for a fresh compile on every launch.
    public static func make(
        domains: [String],
        resourceTypes: [String] = TrackerBlockerCatalog.resourceTypes,
        thirdPartyOnly: Bool = true,
        exceptionHosts: [String] = []
    ) -> String {
        let orderedDomains = Array(Set(domains)).sorted()
        let orderedExceptions = Array(Set(exceptionHosts)).sorted()

        let loadTypeField = thirdPartyOnly ? ",\"load-type\":[\"third-party\"]" : ""
        let resourceTypeField = resourceTypes.isEmpty
            ? ""
            : ",\"resource-type\":\(jsonStringArray(resourceTypes))"
        let exceptionField = orderedExceptions.isEmpty
            ? ""
            : ",\"unless-top-url\":\(jsonStringArray(orderedExceptions.map(topURLFilter)))"

        let rules = orderedDomains.map { domain in
            "{\"trigger\":{\"url-filter\":\"\(jsonEscaped(domainFilter(domain)))\""
                + loadTypeField
                + resourceTypeField
                + exceptionField
                + "},\"action\":{\"type\":\"block\"}}"
        }
        return "[" + rules.joined(separator: ",") + "]"
    }

    /// Matches the domain itself and any subdomain, on http and https, while a
    /// host that merely ends with the same letters (`notdoubleclick.net`) does not.
    static func domainFilter(_ domain: String) -> String {
        "^https?://([^/:]+\\.)?\(regexEscaped(domain))[:/]"
    }

    /// Per-site exceptions are stored without the `www.` prefix, so the
    /// top-URL pattern accepts both spellings of the same site.
    static func topURLFilter(_ host: String) -> String {
        "^https?://(www\\.)?\(regexEscaped(host))[:/]"
    }

    private static let regexMetacharacters: Set<Character> = ["\\", "^", "$", ".", "|", "?", "*", "+", "(", ")", "[", "]", "{", "}"]

    private static func regexEscaped(_ value: String) -> String {
        var escaped = ""
        escaped.reserveCapacity(value.count + 8)
        for character in value {
            if regexMetacharacters.contains(character) { escaped.append("\\") }
            escaped.append(character)
        }
        return escaped
    }

    private static func jsonStringArray(_ values: [String]) -> String {
        "[" + values.map { "\"\(jsonEscaped($0))\"" }.joined(separator: ",") + "]"
    }

    private static func jsonEscaped(_ value: String) -> String {
        var escaped = ""
        escaped.reserveCapacity(value.count + 8)
        for scalar in value.unicodeScalars {
            switch scalar {
            case "\"": escaped += "\\\""
            case "\\": escaped += "\\\\"
            case "\n": escaped += "\\n"
            case "\r": escaped += "\\r"
            case "\t": escaped += "\\t"
            default:
                if scalar.value < 0x20 {
                    escaped += String(format: "\\u%04x", scalar.value)
                } else {
                    escaped.unicodeScalars.append(scalar)
                }
            }
        }
        return escaped
    }
}

public enum StableHash {
    /// FNV-1a 64. Swift's `Hasher` is seeded per process, so it cannot be used
    /// for values that must stay identical across launches, such as the
    /// compiled rule-list identifier.
    public static func fnv1a64(_ value: String) -> UInt64 {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in value.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01b3
        }
        return hash
    }

    public static func fnv1a64Hex(_ value: String) -> String {
        String(format: "%016lx", fnv1a64(value))
    }
}
