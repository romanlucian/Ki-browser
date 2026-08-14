import ClearframeCore
import SwiftUI

/// Deterministic per-site accent color for tab and bookmark identity dots.
/// The same normalized host always maps to the same color, in this run and
/// every future one, because it hashes with `StableHash.fnv1a64` rather than
/// Swift's per-process-seeded `Hasher` (see `TrackerBlockerCatalog.swift`).
/// There is no favicon fetch and no network access — the color is derived
/// entirely from the host string already available on the tab/bookmark.
enum IdentityColor {
    /// Lowercases and strips a leading "www." — the same normalization
    /// `ContentBlockingSettingsStore` applies to site exceptions — so
    /// "example.com" and "www.example.com" always land on the same color.
    static func normalizedHost(_ host: String) -> String {
        let trimmed = host.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return trimmed.hasPrefix("www.") ? String(trimmed.dropFirst(4)) : trimmed
    }

    /// The identity color for `host`. Empty or whitespace-only input (a new
    /// tab, an unparsed bookmark URL) always returns `fallback` rather than
    /// hashing into a misleading palette entry.
    static func color(forHost host: String) -> Color {
        let normalized = normalizedHost(host)
        guard !normalized.isEmpty else { return fallback }
        let index = Int(StableHash.fnv1a64(normalized) % UInt64(palette.count))
        return palette[index]
    }

    /// Neutral and desaturated so it is never mistaken for a real palette
    /// entry.
    static let fallback = Color(hue: 0, saturation: 0, brightness: 0.5)

    /// Twelve hues spread across two arcs, both chosen to stay clear of the
    /// accent mint (~132°) and the private-tab purple (~280°) so an
    /// identity dot is never confused with either.
    private static let paletteHueDegrees: [Double] = [
        5, 25, 45, 65, 85, 185, 205, 225, 245, 315, 335, 350
    ]

    private static let palette: [Color] = paletteHueDegrees.map {
        Color(hue: $0 / 360, saturation: 0.55, brightness: 0.85)
    }
}
