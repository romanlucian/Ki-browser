import Foundation

/// The browser's platform-neutral layer: models, stores, the session, the
/// workspace and the assistant. Everything here compiles for macOS and iOS.
///
/// **There is no `#if os(...)` in this target.** Where a platform differs, the
/// difference enters through a protocol whose implementation lives in that
/// platform's own target. A conditional here would mean two behaviours behind
/// one name, which is what this boundary exists to prevent.
public enum LimeghostShared {
    /// Linked and reachable. Asserted by `PlatformSurfaceTests` so a missing or
    /// misconfigured target fails as a test rather than as a mystery later.
    public static let frameworkIsReachable = true
}
