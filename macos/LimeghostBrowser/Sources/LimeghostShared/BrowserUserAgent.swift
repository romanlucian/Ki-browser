import Foundation

/// What Limeghost tells websites it is.
///
/// A `WKWebView` identifies itself as bare WebKit — no `Version/` or `Safari/`
/// token — and sites that tailor pages by user agent read that as an engine
/// they do not know. Google, for one, answers it with a stripped-down page
/// kept for unrecognised clients: no dark mode, no current features, markup
/// from another era. The pages were never broken; they were never offered.
///
/// Limeghost renders with WebKit, the same engine Safari ships, so it
/// presents Safari's user agent. That is a statement about the engine, and it
/// is true: what a site sends Safari is what Limeghost can draw. The Safari
/// version is read from the copy installed on this Mac so it stays current on
/// its own rather than rotting into another stale claim.
public enum BrowserUserAgent {
    /// WebKit's own build token, stable across recent Safari releases.
    public static let safariBuild = "605.1.15"

    /// Used when Safari cannot be read: always on a phone, which has no
    /// Safari.app to read, and on a Mac only in a restricted sandbox. On iOS
    /// Safari ships with the system, so the system's version is Safari's; it
    /// used to be a fixed "26.5" whatever the phone ran.
    static var fallbackSafariVersion: String {
        fallbackVersion(for: ProcessInfo.processInfo.operatingSystemVersion)
    }

    static func fallbackVersion(for system: OperatingSystemVersion) -> String {
        "\(system.majorVersion).\(system.minorVersion)"
    }

    private static let safariInfoPlist = "/Applications/Safari.app/Contents/Info.plist"

    /// Appended to `WKWebView`'s default user agent, which already carries the
    /// platform and `AppleWebKit/` build.
    ///
    /// Setting a configuration's application name *replaces* the one WebKit
    /// gave it, and on an iPhone that one is the `Mobile/…` token. Dropping it
    /// made the phone announce itself without "Mobile", and sites that choose
    /// their layout by looking for "Mobi" — the check MDN recommends — sent it
    /// their desktop pages. So the platform's own token is passed in and kept,
    /// where Safari keeps it: after the version. A Mac has none.
    public static func applicationName(platformDefault: String?) -> String {
        applicationName(platformDefault: platformDefault, safariVersion: installedSafariVersion)
    }

    static func applicationName(platformDefault: String?, safariVersion: String) -> String {
        let platformToken = platformDefault?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let middle = platformToken.isEmpty ? "" : "\(platformToken) "
        return "Version/\(safariVersion) \(middle)Safari/\(safariBuild)"
    }

    public static var installedSafariVersion: String {
        version(fromInfoPlistAt: safariInfoPlist) ?? fallbackSafariVersion
    }

    /// Split out so a test can read a plist it controls instead of the Mac's.
    public static func version(fromInfoPlistAt path: String) -> String? {
        guard let info = NSDictionary(contentsOfFile: path),
              let version = info["CFBundleShortVersionString"] as? String else { return nil }
        let trimmed = version.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
