import Foundation

/// What Clearframe tells websites it is.
///
/// A `WKWebView` identifies itself as bare WebKit — no `Version/` or `Safari/`
/// token — and sites that tailor pages by user agent read that as an engine
/// they do not know. Google, for one, answers it with a stripped-down page
/// kept for unrecognised clients: no dark mode, no current features, markup
/// from another era. The pages were never broken; they were never offered.
///
/// Clearframe renders with WebKit, the same engine Safari ships, so it
/// presents Safari's user agent. That is a statement about the engine, and it
/// is true: what a site sends Safari is what Clearframe can draw. The Safari
/// version is read from the copy installed on this Mac so it stays current on
/// its own rather than rotting into another stale claim.
enum BrowserUserAgent {
    /// WebKit's own build token, stable across recent Safari releases.
    static let safariBuild = "605.1.15"

    /// Used only when Safari cannot be read — a restricted sandbox, or a Mac
    /// without it. Keep it recent when this file is touched.
    static let fallbackSafariVersion = "26.5"

    private static let safariInfoPlist = "/Applications/Safari.app/Contents/Info.plist"

    /// Appended to `WKWebView`'s default user agent, which already carries the
    /// platform and `AppleWebKit/` build.
    static var applicationName: String {
        "Version/\(installedSafariVersion) Safari/\(safariBuild)"
    }

    static var installedSafariVersion: String {
        version(fromInfoPlistAt: safariInfoPlist) ?? fallbackSafariVersion
    }

    /// Split out so a test can read a plist it controls instead of the Mac's.
    static func version(fromInfoPlistAt path: String) -> String? {
        guard let info = NSDictionary(contentsOfFile: path),
              let version = info["CFBundleShortVersionString"] as? String else { return nil }
        let trimmed = version.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
