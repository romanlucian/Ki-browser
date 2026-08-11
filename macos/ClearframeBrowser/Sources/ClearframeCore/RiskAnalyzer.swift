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
        if page.hostname.hasPrefix("xn--") || page.hostname.contains(".xn--") {
            add(25, "Encoded domain name", "Internationalized domains can be legitimate, but deserve a closer look.")
        }
        if page.hostname.split(separator: ".").count == 4,
           page.hostname.split(separator: ".").allSatisfy({ Int($0) != nil }) {
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
            (["act immediately", "act now", "final warning", "account will be suspended"], 10, "Urgency or account-threat language", "Pressure to act immediately can prevent careful checking."),
            (["anydesk", "teamviewer", "remote access"], 18, "Remote-access language", "Unexpected requests to install remote-access software are high risk.")
        ]

        for pattern in patterns where pattern.terms.contains(where: lowerText.contains) {
            add(pattern.points, pattern.title, pattern.detail)
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

    private static func origin(_ url: URL) -> String? {
        guard let scheme = url.scheme, let host = url.host else { return nil }
        if let port = url.port {
            return "\(scheme)://\(host):\(port)"
        }
        return "\(scheme)://\(host)"
    }
}
