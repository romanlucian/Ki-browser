import LimeghostCore
import Foundation

/// One place a person could import bookmarks from: a Chromium profile
/// Limeghost found on this Mac, Safari, or a file the person picks
/// themselves. Building this list never reads a bookmarks file — only enough
/// of the filesystem to say what exists and what to call it.
struct DetectedBookmarkSource: Identifiable, Equatable {
    enum Kind: Equatable {
        case chromium
        case safari
        case file
    }

    let id: String
    /// What the source list shows — for a Chromium profile this includes the
    /// profile's own name ("Chrome — Lucian Roman") so choosing among many
    /// profiles is unambiguous.
    let title: String
    let kind: Kind
    /// The `Bookmarks` file to read. `nil` for Safari (permission makes a
    /// direct read unreliable — see `BookmarkImportSourceDiscovery`) and for
    /// "Choose a file…" (there is nothing to read until the person picks
    /// one).
    let bookmarksFileURL: URL?
    /// The plain name used when naming the destination folder — "Chrome",
    /// not "Chrome — Lucian Roman": the profile detail belongs in the source
    /// list, not repeated on every folder it creates.
    let folderNamingLabel: String
}

/// Reads a Chromium `Local State` file for the human-chosen name behind each
/// profile's folder name ("Default", "Profile 1", …). Pure JSON parsing, no
/// filesystem access of its own, so it can be exercised with a synthetic
/// fixture instead of a real profile.
enum ChromiumProfileNaming {
    /// Every display name `Local State` has recorded, keyed by profile
    /// directory name. Missing or malformed input simply yields an empty
    /// map — callers fall back to the directory name themselves.
    static func displayNames(fromLocalState data: Data) -> [String: String] {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let profile = object["profile"] as? [String: Any],
              let infoCache = profile["info_cache"] as? [String: Any] else {
            return [:]
        }
        var result: [String: String] = [:]
        for (directoryName, value) in infoCache {
            guard let entry = value as? [String: Any],
                  let name = (entry["name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !name.isEmpty else { continue }
            result[directoryName] = name
        }
        return result
    }

    /// The label to show for one profile directory: its recorded name when
    /// `Local State` has one, otherwise the directory name itself — "Profile
    /// 1" reads fine on its own when nothing else is known.
    static func displayName(forProfileDirectory directory: String, localState data: Data?) -> String {
        guard let data, let name = displayNames(fromLocalState: data)[directory] else { return directory }
        return name
    }
}

/// Finds the bookmark sources Limeghost can offer without the person typing
/// a path: every Chromium-family profile with a readable `Bookmarks` file,
/// Safari, and the standing "Choose a file…" option.
enum BookmarkImportSourceDiscovery {
    private struct ChromiumBrowser {
        let displayName: String
        /// Relative to Application Support. macOS has no `User Data`
        /// segment — that path component exists only on Windows.
        let relativePath: String
    }

    private static let chromiumBrowsers: [ChromiumBrowser] = [
        ChromiumBrowser(displayName: "Chrome", relativePath: "Google/Chrome"),
        ChromiumBrowser(displayName: "Brave", relativePath: "BraveSoftware/Brave-Browser"),
        ChromiumBrowser(displayName: "Microsoft Edge", relativePath: "Microsoft Edge")
    ]

    static let safariBookmarksPath = "Library/Safari/Bookmarks.plist"
    /// Opens System Settings directly at the Full Disk Access pane. There is
    /// no API to request the permission itself — this only saves the person
    /// the navigation once they decide to grant it.
    static let fullDiskAccessSettingsURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")!

    /// - Parameter applicationSupportOverride: exists so a test can point
    ///   discovery at a synthetic directory instead of the real
    ///   `~/Library/Application Support`. Production call sites leave it
    ///   `nil`.
    static func detectSources(
        fileManager: FileManager = .default,
        applicationSupportOverride: URL? = nil
    ) -> [DetectedBookmarkSource] {
        let base = applicationSupportOverride
            ?? fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        var sources: [DetectedBookmarkSource] = []
        if let base {
            for browser in chromiumBrowsers {
                sources += detectProfiles(of: browser, under: base, fileManager: fileManager)
            }
        }
        sources.append(DetectedBookmarkSource(
            id: "safari",
            title: "Safari",
            kind: .safari,
            bookmarksFileURL: safariBookmarksURL(fileManager: fileManager),
            folderNamingLabel: "Safari"
        ))
        sources.append(DetectedBookmarkSource(
            id: "file",
            title: "Choose a file…",
            kind: .file,
            bookmarksFileURL: nil,
            folderNamingLabel: "a file"
        ))
        return sources
    }

    static func safariBookmarksURL(fileManager: FileManager = .default) -> URL {
        fileManager.homeDirectoryForCurrentUser.appendingPathComponent(safariBookmarksPath)
    }

    private static func detectProfiles(
        of browser: ChromiumBrowser,
        under applicationSupport: URL,
        fileManager: FileManager
    ) -> [DetectedBookmarkSource] {
        let root = applicationSupport.appendingPathComponent(browser.relativePath, isDirectory: true)
        guard let entries = try? fileManager.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) else {
            return []
        }
        let localStateData = try? Data(contentsOf: root.appendingPathComponent("Local State"))

        let profileDirectories = entries
            .map(\.lastPathComponent)
            .filter { $0 == "Default" || $0.hasPrefix("Profile ") }
            .sorted(by: profileDirectoryOrder)

        return profileDirectories.compactMap { directoryName in
            let bookmarksURL = root.appendingPathComponent(directoryName).appendingPathComponent("Bookmarks")
            guard fileManager.fileExists(atPath: bookmarksURL.path) else { return nil }
            let label = ChromiumProfileNaming.displayName(forProfileDirectory: directoryName, localState: localStateData)
            let title = label == directoryName ? "\(browser.displayName) — \(directoryName)" : "\(browser.displayName) — \(label)"
            return DetectedBookmarkSource(
                id: "\(browser.relativePath)/\(directoryName)",
                title: title,
                kind: .chromium,
                bookmarksFileURL: bookmarksURL,
                folderNamingLabel: browser.displayName
            )
        }
    }

    /// "Default" first, then "Profile 1", "Profile 2", … in numeric order —
    /// plain lexicographic sorting would put "Profile 10" before "Profile
    /// 2".
    private static func profileDirectoryOrder(_ lhs: String, _ rhs: String) -> Bool {
        if lhs == "Default" { return rhs != "Default" }
        if rhs == "Default" { return false }
        let leftNumber = Int(lhs.dropFirst("Profile ".count))
        let rightNumber = Int(rhs.dropFirst("Profile ".count))
        if let leftNumber, let rightNumber { return leftNumber < rightNumber }
        return lhs < rhs
    }
}
