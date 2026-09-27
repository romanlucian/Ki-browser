import Foundation

/// Waits for a condition the way the phone's tests need to wait for one.
///
/// **One helper, not a copy per file.** There were two — five seconds in
/// `ReaderOnThePhoneTests` and three in `IOSSessionPlatformTests` — and
/// neither had learned what the shared layer's own `eventually` already knew,
/// because a lesson written into one copy does not reach the others.
///
/// The default is thirty seconds because **the first page WebKit loads in a
/// fresh Simulator process can take far longer than a few seconds**: measured
/// at 64 seconds on September 22, 2026, with every later page about one. A met
/// condition returns at once, so a long ceiling costs nothing whenever things
/// work — it is paid only by a test that was going to fail anyway. A short one
/// is paid by every cold runner.
///
/// `ReaderOnThePhoneTests.testAFailedLoadIsSaidOverThePage` is what proved it:
/// green on this machine for two weeks, then on CI, on September 27, 2026,
/// "the unreachable address did not fail" after 5.7 seconds — WebKit had not
/// yet reported a refused connection to `127.0.0.1:65530`, which is not the
/// same thing as the connection having succeeded.
///
/// Do not raise this much further to cover a *stall*. The shared suite has
/// seen one web process hang for 956 seconds on CI while its neighbours loaded
/// pages normally, and a ceiling set to cover that would make a real
/// regression in page loading take hours to fail on the Mac.
@MainActor
func eventually(timeout: TimeInterval = 30, _ condition: @MainActor () -> Bool) async -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
        if condition() { return true }
        try? await Task.sleep(nanoseconds: 50_000_000)
    }
    return condition()
}
