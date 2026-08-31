import Foundation

public enum RiskAnalyzer {
    public static func assess(page: PageSnapshot) -> RiskAssessment {
        var signals: [RiskSignal] = []
        let lowerText = String(page.text.prefix(30_000)).lowercased()

        func add(_ points: Int, _ title: String, _ detail: String) {
            signals.append(RiskSignal(points: points, title: title, detail: detail))
        }

        if page.scheme.lowercased() == "http" {
            add(20, "Connection is not encrypted", "Information sent to this page may be exposed in transit.")
        }
        if page.hasPasswordField && page.scheme.lowercased() == "http" {
            add(40, "Password requested on an unencrypted page", "Do not enter a password here.")
        }
        let normalizedHost = page.hostname.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
        if normalizedHost.hasPrefix("xn--") || normalizedHost.contains(".xn--") {
            add(25, "Encoded domain name", "Internationalized domains can be legitimate, but deserve a closer look.")
        }
        if isIPAddress(normalizedHost) {
            add(20, "Site uses a raw IP address", "Most consumer services use a recognizable domain name.")
        }

        if let pageOrigin = URL(string: page.url).flatMap(origin),
           page.formActions.contains(where: { action in
               guard let actionURL = URL(string: action), let actionOrigin = origin(actionURL) else { return false }
               return actionOrigin != pageOrigin
           }) {
            add(15, "A form sends data to another site", "That can be normal for payments, but confirm the destination before submitting.")
        }

        let patterns: [(terms: [String], points: Int, title: String, detail: String)] = [
            (["seed phrase", "recovery phrase", "private key"], 35, "Requests a wallet secret", "Legitimate support should never ask for a seed phrase or private key."),
            (["gift card", "wire transfer", "pay in bitcoin", "pay in crypto"], 18, "Hard-to-reverse payment language", "Gift cards, wire transfers, and crypto payments are common in scams."),
            (["guaranteed returns", "double your money", "risk-free investment"], 25, "Implausible financial promise", "Guaranteed or risk-free returns are a serious warning sign."),
            (["act immediately", "act now", "final warning", "account will be suspended"], 10, "Urgency or account-threat language", "Pressure to act immediately can prevent careful checking.")
        ]

        for pattern in patterns where pattern.terms.contains(where: lowerText.contains) {
            add(pattern.points, pattern.title, pattern.detail)
        }
        if containsContextualRemoteAccessRequest(lowerText) {
            add(
                20,
                "Remote-access request",
                "The page combines remote-access software with instructions and pressure or support/payment context. Confirm the request independently before continuing."
            )
        }

        let score = min(100, signals.reduce(0) { $0 + $1.points })
        let level: RiskLevel = score >= 40 ? .high : score >= 20 ? .caution : .low
        return RiskAssessment(
            score: score,
            level: level,
            signals: signals,
            secureConnection: page.scheme.lowercased() == "https"
        )
    }

    private static func origin(_ url: URL) -> Origin? {
        guard let scheme = url.scheme?.lowercased(),
              let host = url.host?.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: ".")) else {
            return nil
        }
        let defaultPort = scheme == "https" ? 443 : (scheme == "http" ? 80 : nil)
        return Origin(scheme: scheme, host: host, port: url.port == defaultPort ? nil : url.port)
    }

    private static func isIPAddress(_ host: String) -> Bool {
        let unwrapped = host.trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
        if isIPv4Address(unwrapped) { return true }
        guard unwrapped.contains(":"),
              !unwrapped.contains(":::"),
              unwrapped.allSatisfy({ $0.isHexDigit || $0 == ":" || $0 == "." }) else { return false }
        let compressionParts = unwrapped.components(separatedBy: "::")
        guard compressionParts.count <= 2 else { return false }

        let groups = unwrapped.split(separator: ":", omittingEmptySubsequences: true)
        var representedGroupCount = 0
        for (index, group) in groups.enumerated() {
            if group.contains(".") {
                guard index == groups.count - 1, isIPv4Address(String(group)) else { return false }
                representedGroupCount += 2
            } else {
                guard (1...4).contains(group.count), group.allSatisfy(\.isHexDigit) else { return false }
                representedGroupCount += 1
            }
        }
        return compressionParts.count == 2 ? representedGroupCount < 8 : representedGroupCount == 8
    }

    private static func isIPv4Address(_ value: String) -> Bool {
        let octets = value.split(separator: ".", omittingEmptySubsequences: false)
        return octets.count == 4 && octets.allSatisfy { part in
            guard !part.isEmpty, part.count <= 3, part.allSatisfy(\.isNumber), let number = Int(part) else {
                return false
            }
            return (0...255).contains(number)
        }
    }

    /// Merely discussing remote-desktop software is ordinary technical content.
    /// Raise a signal only when a nearby passage also asks for an action and uses
    /// pressure, support, account, security, or payment context typical of a request.
    private static func containsContextualRemoteAccessRequest(_ text: String) -> Bool {
        let remoteTerms = ["anydesk", "teamviewer", "remote desktop", "remote access"]
        let actionTerms = [
            "install", "download", "open", "run", "launch", "connect", "allow",
            "grant", "give", "provide", "share", "enable"
        ]
        let contextTerms = [
            "support", "technician", "refund", "bank", "payment", "account",
            "security alert", "virus", "infected", "immediately", "urgent", "now",
            "verify", "call"
        ]

        for remoteTerm in remoteTerms {
            var searchRange = text.startIndex..<text.endIndex
            while let match = text.range(of: remoteTerm, range: searchRange) {
                let windowStart = text.index(match.lowerBound, offsetBy: -180, limitedBy: text.startIndex)
                    ?? text.startIndex
                let windowEnd = text.index(match.upperBound, offsetBy: 180, limitedBy: text.endIndex)
                    ?? text.endIndex
                let window = String(text[windowStart..<windowEnd])
                if actionTerms.contains(where: { containsWholeTerm($0, in: window) }) &&
                    contextTerms.contains(where: { containsWholeTerm($0, in: window) }) {
                    return true
                }
                searchRange = match.upperBound..<text.endIndex
            }
        }
        return false
    }

    private static func containsWholeTerm(_ term: String, in text: String) -> Bool {
        let pattern = "\\b\(NSRegularExpression.escapedPattern(for: term))\\b"
        return text.range(of: pattern, options: .regularExpression) != nil
    }
}

private struct Origin: Equatable {
    let scheme: String
    let host: String
    let port: Int?
}
