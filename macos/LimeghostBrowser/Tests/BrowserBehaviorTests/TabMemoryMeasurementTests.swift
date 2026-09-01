import LimeghostCore
import WebKit
import XCTest
@testable import LimeghostBrowser

/// Measures what open tabs actually cost, before anything is built to reduce it.
///
/// Tab hibernation is worth doing only if the number moves. `AICompanion`'s
/// two-session cap was justified by measurement — a hidden `WKWebView` does not
/// release its memory, because WebKit holds a "recently visible" claim for four
/// minutes and suspension pauses rather than discards — and the same standard
/// applies here rather than an assumption that twenty tabs must be expensive.
///
/// Skipped unless `LIMEGHOST_TAB_MEMORY=1`, because it opens real web views and
/// takes a while. It is a measuring instrument, not a regression test: it
/// asserts nothing about the numbers and only fails if it cannot collect them.
///
/// Run it as:
///
///     LIMEGHOST_TAB_MEMORY=1 LIMEGHOST_TAB_COUNT=20 \
///       swift test --filter testMeasureWhatOpenTabsCost
///
/// Deliberately not driven through the installed app: that would add tabs to
/// somebody's real saved session.
@MainActor
final class TabMemoryMeasurementTests: XCTestCase {
    /// Every WebKit content process alive right now, and what it is holding.
    ///
    /// Read from `ps` rather than `task_info`, because the interesting figure
    /// belongs to other processes: WebKit runs page content out of process, so
    /// the test process's own footprint says almost nothing about what tabs
    /// cost.
    private struct WebContentFootprint {
        let processCount: Int
        /// Resident set size across every WebContent process, in megabytes.
        let residentMB: Double
    }

    /// Every WebKit content process on the Mac right now, by pid and size.
    ///
    /// Attribution is by pid set, not by parent: WebContent runs as an XPC
    /// service and its parent is launchd, so every one of them looks the same
    /// from the outside. Taking the set before and after tells us exactly which
    /// processes this measurement created, and leaves Safari and the user's
    /// other WebKit apps out of the arithmetic.
    ///
    /// The first version of this summed every WebContent process on the machine
    /// and reported memory *rising* after twenty tabs were destroyed — that was
    /// somebody else's browser allocating, not ours.
    private func webContentProcesses() -> [Int: Double] {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/sh")
        task.arguments = ["-c", "ps -Ao pid,rss,comm | grep '[W]ebKit.WebContent' | awk '{print $1, $2}'"]
        let pipe = Pipe()
        task.standardOutput = pipe
        try? task.run()
        task.waitUntilExit()
        let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        var result: [Int: Double] = [:]
        for line in output.split(separator: "\n") {
            let parts = line.split(separator: " ")
            guard parts.count == 2, let pid = Int(parts[0]), let rss = Double(parts[1]) else { continue }
            result[pid] = rss / 1024
        }
        return result
    }

    func testMeasureWhatOpenTabsCost() throws {
        guard ProcessInfo.processInfo.environment["LIMEGHOST_TAB_MEMORY"] != nil else {
            throw XCTSkip("Set LIMEGHOST_TAB_MEMORY=1 to measure what open tabs cost.")
        }
        let tabCount = ProcessInfo.processInfo.environment["LIMEGHOST_TAB_COUNT"]
            .flatMap(Int.init) ?? 20

        let before = Set(webContentProcesses().keys)

        // A page with real markup, styling and script, served locally so the
        // measurement is not a measurement of somebody's network.
        let html = """
        <!doctype html><html><head><meta charset="utf-8"><title>Measurement</title>
        <style>body{font:16px/1.6 -apple-system;margin:40px;max-width:40em}
        h1{font-size:2em}p{margin:1em 0}</style></head><body>
        <h1>A page with enough in it to cost something</h1>
        \(String(repeating: "<p>Paragraphs of ordinary prose, repeated so the document has real length and the layout engine has real work to do.</p>", count: 120))
        <script>document.title = "Measured " + document.querySelectorAll("p").length;</script>
        </body></html>
        """

        var sessions: [BrowserSession] = []
        for index in 0..<tabCount {
            let session = BrowserSession(
                downloadCenter: DownloadCenter(),
                searchSettings: SearchSettingsStore(
                    defaults: UserDefaults(suiteName: "limeghost.measure.\(UUID().uuidString)")!
                )
            )
            sessions.append(session)
            session.webView.loadHTMLString(html, baseURL: URL(string: "https://measurement.invalid/\(index)"))
        }

        // Let the content processes come up and lay the pages out. Polling
        // rather than a fixed sleep, so a fast machine is not punished and a
        // slow one is not measured mid-launch.
        let deadline = Date().addingTimeInterval(60)
        while Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.5))
            if Set(webContentProcesses().keys).subtracting(before).count >= tabCount { break }
        }
        // A further settle: WebKit keeps allocating after the first paint.
        RunLoop.current.run(until: Date().addingTimeInterval(5))

        let loadedAll = webContentProcesses()
        let ours = Set(loadedAll.keys).subtracting(before)
        let loadedMB = ours.reduce(0.0) { $0 + (loadedAll[$1] ?? 0) }
        let perTabMB = tabCount > 0 ? loadedMB / Double(tabCount) : 0

        print("""

        -- what \(tabCount) open tabs cost -------------------------------
          content processes ours   \(ours.count)   (of \(loadedAll.count) on this Mac)
          resident, ours only      \(String(format: "%.0f", loadedMB)) MB
          per tab                  \(String(format: "%.1f", perTabMB)) MB
        ------------------------------------------------------------

        """)

        XCTAssertFalse(ours.isEmpty, "no content processes were attributed to this measurement")

        // The decisive figure. Hibernation is worth building only if letting a
        // session go actually returns the memory. CLAUDE.md already records
        // that a *hidden* WKWebView does not, because WebKit holds a
        // "recently visible" claim for about four minutes and suspension pauses
        // rather than discards — so a short wait here would measure that claim
        // rather than the release.
        sessions.forEach { $0.teardown() }
        sessions.removeAll()

        let releaseWait = ProcessInfo.processInfo.environment["LIMEGHOST_RELEASE_WAIT"]
            .flatMap(Double.init) ?? 20
        let releaseDeadline = Date().addingTimeInterval(releaseWait)
        while Date() < releaseDeadline {
            RunLoop.current.run(until: Date().addingTimeInterval(1))
            if Set(webContentProcesses().keys).intersection(ours).isEmpty { break }
        }

        let afterAll = webContentProcesses()
        let survivors = Set(afterAll.keys).intersection(ours)
        let survivingMB = survivors.reduce(0.0) { $0 + (afterAll[$1] ?? 0) }
        let reclaimedMB = loadedMB - survivingMB

        print("""

        -- and what letting them go gives back (waited up to \(String(format: "%.0f", releaseWait))s) --
          processes still alive    \(survivors.count) of \(ours.count)
          resident still held      \(String(format: "%.0f", survivingMB)) MB of \(String(format: "%.0f", loadedMB)) MB
          reclaimed                \(String(format: "%.0f", reclaimedMB)) MB  (\(String(format: "%.0f", loadedMB > 0 ? reclaimedMB / loadedMB * 100 : 0))%)
        ------------------------------------------------------------

        """)
    }
}
