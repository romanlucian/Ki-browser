import ClearframeCore
import SwiftUI

/// The eight colors a tab group can take, tuned for the Halo chrome.
///
/// `ClearframeCore` stores only the identifier (`TabGroupRecord.colorIDs`);
/// the colors themselves are UI, and live here with the rest of the chrome
/// tokens. Two constraints shape the values:
///
/// - every color has to read as itself at 8pt against `bg2` (#101013), so
///   nothing drops below 0.72 brightness;
/// - none of them may be mistaken for the product's own signals — the mint
///   accent (~132°) or the private-tab purple (~280°) — so the green sits at
///   92° where it reads as leaf rather than mint, and the purple at 288° where
///   it reads as violet.
enum TabGroupPalette {
    struct Entry: Identifiable, Equatable {
        let id: String
        /// Shown in the color menu and read aloud by VoiceOver.
        let name: String
        let color: Color
    }

    static let entries: [Entry] = [
        Entry(id: "grey", name: "Grey", color: Color(hue: 220 / 360, saturation: 0.09, brightness: 0.74)),
        Entry(id: "blue", name: "Blue", color: Color(hue: 212 / 360, saturation: 0.62, brightness: 0.93)),
        Entry(id: "red", name: "Red", color: Color(hue: 358 / 360, saturation: 0.56, brightness: 0.95)),
        Entry(id: "yellow", name: "Yellow", color: Color(hue: 44 / 360, saturation: 0.70, brightness: 0.95)),
        Entry(id: "green", name: "Green", color: Color(hue: 92 / 360, saturation: 0.52, brightness: 0.80)),
        Entry(id: "pink", name: "Pink", color: Color(hue: 330 / 360, saturation: 0.48, brightness: 0.95)),
        Entry(id: "purple", name: "Purple", color: Color(hue: 288 / 360, saturation: 0.46, brightness: 0.93)),
        Entry(id: "cyan", name: "Cyan", color: Color(hue: 190 / 360, saturation: 0.58, brightness: 0.89))
    ]

    static func entry(for colorID: String) -> Entry {
        let normalized = TabGroupRecord.normalizedColorID(colorID)
        return entries.first { $0.id == normalized } ?? entries[0]
    }

    static func color(for colorID: String) -> Color {
        entry(for: colorID).color
    }

    static func name(for colorID: String) -> String {
        entry(for: colorID).name
    }

    // MARK: - Group surfaces

    /// The enclosure behind a group's tabs: present enough to bound the run,
    /// quiet enough that the tab chips stay the loudest thing in the strip.
    static func enclosureFill(for colorID: String) -> Color {
        color(for: colorID).opacity(0.15)
    }

    static func enclosureHairline(for colorID: String) -> Color {
        color(for: colorID).opacity(0.45)
    }

    static func chipFill(for colorID: String, isHovered: Bool) -> Color {
        color(for: colorID).opacity(isHovered ? 0.30 : 0.20)
    }

    static func chipHairline(for colorID: String) -> Color {
        color(for: colorID).opacity(0.55)
    }
}

extension TabGroupRecord {
    /// What the strip and the menus call this group. An unnamed group shows a
    /// colored dot rather than filler text, so this name is only used where
    /// words are required.
    var displayName: String {
        title.isEmpty ? "\(TabGroupPalette.name(for: colorID)) group" : title
    }
}
