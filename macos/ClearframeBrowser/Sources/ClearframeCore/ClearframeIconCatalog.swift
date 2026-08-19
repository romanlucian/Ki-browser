import Foundation

/// One icon in the shipped Clearframe set: a stable identifier, the group the
/// picker files it under, and the artwork itself.
///
/// `markup` is the drawing, held exactly as it was drawn — a 16x16 box of
/// stroke-only geometry. It is deliberately not pre-parsed here: `ClearframeCore`
/// stays Foundation-only, and the UI layer turns markup into a drawable path
/// once per icon through `VectorPathParser`.
public struct ClearframeIcon: Equatable, Identifiable, Sendable {
    public let id: String
    public let category: ClearframeIconCategory
    public let markup: String
    /// Which shipped set this icon belongs to. Drives how it is drawn and
    /// whether a folder tint can reach it.
    public let style: ClearframeIconStyle
    /// The coordinate box the artwork was drawn in. The Clearframe set is a
    /// 16x16 square; a licensed set brings its own, sometimes with a non-zero
    /// origin, so the renderer must be told rather than assume.
    public let box: VectorBox

    public init(
        id: String,
        category: ClearframeIconCategory,
        markup: String,
        style: ClearframeIconStyle = .clearframe,
        box: VectorBox = .sixteen
    ) {
        self.id = id
        self.category = category
        self.markup = markup
        self.style = style
        self.box = box
    }

    /// The name without its set prefix: what the picker labels a cell with, and
    /// what someone typing "mail" is actually looking for. Identifiers stay
    /// prefixed because they are the stored value and must not collide.
    public var displayName: String {
        let prefix = style.identifierPrefix
        return prefix.isEmpty ? id : String(id.dropFirst(prefix.count))
    }
}

/// The rectangle an icon's coordinates live in — an SVG `viewBox`, kept as a
/// value type so `ClearframeCore` stays Foundation-only.
public struct VectorBox: Equatable, Sendable {
    public let x: Double
    public let y: Double
    public let width: Double
    public let height: Double

    /// The Clearframe set's own box.
    public static let sixteen = VectorBox(x: 0, y: 0, width: 16, height: 16)

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }
}

/// The icon sets the app ships.
///
/// Clearframe's own set is the default and the only tintable one: it is drawn
/// in a single stroke weight with no colour of its own, which is exactly what
/// lets a folder recolour it. The licensed Stickies sets carry their own
/// colours, so a tint has nothing to act on — that is a property of the
/// artwork, not a gap in the picker.
public enum ClearframeIconStyle: String, CaseIterable, Sendable {
    case clearframe
    case stickiesPlain
    case stickiesDuo
    case emojiOne

    public var title: String {
        switch self {
        case .clearframe: return "Clearframe"
        case .stickiesPlain: return "Stickies"
        case .stickiesDuo: return "Stickies Duo"
        case .emojiOne: return "Emoji"
        }
    }

    /// A one-line note the picker can show under the style, so the difference
    /// is visible before a folder commits to it.
    public var subtitle: String {
        switch self {
        case .clearframe: return "Line icons you can tint"
        case .stickiesPlain: return "Colourful, fixed colours"
        case .stickiesDuo: return "Colourful with a shadow, fixed colours"
        case .emojiOne: return "Full-colour emoji, fixed colours"
        }
    }

    /// Stroke width in the artwork's own units. The Clearframe set is drawn at
    /// 1.5 in a 16 box; the Stickies sets at 1 in a 40 box.
    public var strokeWidth: Double {
        switch self {
        case .clearframe: return 1.5
        case .stickiesPlain, .stickiesDuo: return 1
        // The emoji set is filled artwork; the handful of strokes it does
        // carry name their own width, and one unit in a 64 box is the closest
        // equivalent of a hairline.
        case .emojiOne: return 1
        }
    }

    /// How a stroke ends and turns a corner when the artwork does not say.
    ///
    /// The Clearframe set is drawn to be rounded throughout, so that is its
    /// default. A licensed set follows SVG's own defaults, and imposing round
    /// joins on it visibly blunts every sharp point — a star stops having
    /// points. Elements that name a cap or join still win over both.
    public var defaultLineCap: VectorShape.LineCap {
        switch self {
        case .clearframe: return .round
        case .stickiesPlain, .stickiesDuo, .emojiOne: return .butt
        }
    }

    public var defaultLineJoin: VectorShape.LineJoin {
        switch self {
        case .clearframe: return .round
        case .stickiesPlain, .stickiesDuo, .emojiOne: return .miter
        }
    }

    /// Whether a folder's chosen tint reaches this style's artwork.
    public var isTintable: Bool { self == .clearframe }

    /// What every identifier in this style begins with, so identifiers stay
    /// unique across sets without the prefix leaking into the interface.
    public var identifierPrefix: String {
        switch self {
        case .clearframe: return ""
        case .stickiesPlain: return "stickies-"
        case .stickiesDuo: return "stickies-duo-"
        case .emojiOne: return "emoji-"
        }
    }

    /// Attribution the app must show for a style it did not draw. `nil` for
    /// Clearframe's own artwork.
    public var attribution: String? {
        switch self {
        case .clearframe:
            return nil
        case .stickiesPlain, .stickiesDuo:
            return "Stickies by Streamline, CC BY 4.0"
        case .emojiOne:
            return "EmojiOne v1 by Emoji One, CC BY-SA 4.0"
        }
    }
}

/// How the picker groups the set. The order of the cases is the order the
/// picker shows, so this enum is the running order of the whole catalog.
public enum ClearframeIconCategory: String, CaseIterable, Sendable {
    case work
    case creative
    case reading
    case shopping
    case travel
    case code
    case people
    case media
    case home
    case markers
    case nature
    case objects
    case interface
    // Sections the emoji set needs and the drawn sets have no use for. The
    // picker skips a category with nothing in it, so these stay invisible
    // outside the style that fills them.
    case faces
    case food
    case activities
    case symbols
    case flags

    /// The section heading a reader sees.
    public var title: String {
        switch self {
        case .work: return "Work"
        case .creative: return "Creative"
        case .reading: return "Reading"
        case .shopping: return "Shopping"
        case .travel: return "Travel"
        case .code: return "Code"
        case .people: return "People"
        case .media: return "Media"
        case .home: return "Home"
        case .markers: return "Markers"
        case .nature: return "Nature"
        case .objects: return "Objects"
        case .interface: return "Interface"
        case .faces: return "Faces"
        case .food: return "Food"
        case .activities: return "Activities"
        case .symbols: return "Symbols"
        case .flags: return "Flags"
        }
    }
}

/// The folder icons Clearframe ships, and the rules for choosing one.
///
/// Bookmark folders used to carry a single emoji. Those records are never
/// rewritten: a folder keeps whatever emoji it was saved with, and the icon it
/// draws is resolved at render time — an explicitly chosen icon first, then the
/// closest match for its legacy emoji, then the plain folder. That order is the
/// only one any surface should use, through `resolvedIconID(iconID:legacyEmoji:)`.
public enum ClearframeIconCatalog {
    /// Shown by a folder that has chosen nothing, and the fallback for an
    /// identifier this build does not know.
    public static let defaultIconID = "folder"

    /// Every icon the app ships, in catalog order: Clearframe's own set first,
    /// then each licensed set, and within a set category by category.
    ///
    /// Identifiers are unique across the whole list — the licensed sets are
    /// prefixed — so one lookup answers for every style.
    public static let all: [ClearframeIcon] =
        ClearframeIconCatalogData.icons
        + StickiesIconCatalogData.icons
        + EmojiOneIconCatalogData.icons

    private static let index: [String: ClearframeIcon] = Dictionary(
        uniqueKeysWithValues: all.map { ($0.id, $0) }
    )

    private static let byStyle: [ClearframeIconStyle: [ClearframeIcon]] =
        Dictionary(grouping: all, by: \.style)

    private static let byStyleAndCategory: [ClearframeIconStyle: [ClearframeIconCategory: [ClearframeIcon]]] =
        byStyle.mapValues { Dictionary(grouping: $0, by: \.category) }

    /// `nil` for an identifier the catalog does not contain, so a caller can
    /// decide between falling back and reporting the gap.
    public static func icon(id: String) -> ClearframeIcon? {
        index[id]
    }

    /// One style's icons, in catalog order.
    public static func icons(style: ClearframeIconStyle) -> [ClearframeIcon] {
        byStyle[style] ?? []
    }

    /// One style's icons grouped for the picker.
    public static func byCategory(style: ClearframeIconStyle) -> [ClearframeIconCategory: [ClearframeIcon]] {
        byStyleAndCategory[style] ?? [:]
    }

    /// Defaults to Clearframe's own set, which is what every surface outside
    /// the picker means when it asks for a category.
    public static func icons(
        in category: ClearframeIconCategory,
        style: ClearframeIconStyle = .clearframe
    ) -> [ClearframeIcon] {
        byStyleAndCategory[style]?[category] ?? []
    }

    /// The styles that actually shipped artwork, in picker order. Reads the
    /// catalog rather than the enum so a style with no icons never shows an
    /// empty tab.
    public static var availableStyles: [ClearframeIconStyle] {
        ClearframeIconStyle.allCases.filter { !icons(style: $0).isEmpty }
    }

    /// The icon a folder actually draws. Never fails: an unknown identifier and
    /// an unmapped emoji both land on the plain folder rather than leaving a
    /// hole in the bar.
    public static func resolvedIconID(iconID: String?, legacyEmoji: String) -> String {
        if let iconID {
            let trimmed = iconID.trimmingCharacters(in: .whitespacesAndNewlines)
            if index[trimmed] != nil { return trimmed }
        }
        return Self.iconID(forLegacyEmoji: legacyEmoji)
    }

    /// The closest icon for an emoji a folder was saved with. Covers every
    /// emoji the old folder editor offered, plus the ones people commonly typed
    /// into it by hand; anything else becomes the plain folder.
    ///
    /// Pure and total on purpose — migration reads it, and so does every render
    /// site, so it must give the same answer everywhere without touching disk.
    public static func iconID(forLegacyEmoji emoji: String) -> String {
        let key = normalizedEmojiKey(emoji)
        guard !key.isEmpty else { return defaultIconID }
        return legacyEmojiIcons[key] ?? defaultIconID
    }

    /// Strips the variation and skin-tone selectors so "❤️" and "❤" are one
    /// key, and keeps only the first grapheme — the same single character the
    /// folder record stores.
    private static func normalizedEmojiKey(_ emoji: String) -> String {
        let trimmed = emoji.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let first = trimmed.first else { return "" }
        let scalars = first.unicodeScalars.filter { scalar in
            !(0xFE00...0xFE0F).contains(scalar.value) && !(0x1F3FB...0x1F3FF).contains(scalar.value)
        }
        return String(String.UnicodeScalarView(scalars))
    }

    /// Left of the arrow is what the old editor could produce; right of it is
    /// the drawn icon that means the same thing. Keys are stored without
    /// variation selectors — `normalizedEmojiKey` puts a lookup in the same
    /// shape.
    private static let legacyEmojiIcons: [String: String] = [
        // The eight the old picker offered.
        "\u{1F4C1}": "folder",       // 📁
        "\u{1F3A8}": "palette",      // 🎨
        "\u{1F4BB}": "terminal",     // 💻
        "\u{1F6CD}": "bag",          // 🛍️
        "\u{1F4DA}": "library",      // 📚
        "\u{2708}": "plane",         // ✈️
        "\u{1F4A1}": "bolt",         // 💡
        "\u{2764}": "heart",         // ❤️
        // Common hand-typed choices.
        "\u{1F4F7}": "camera",       // 📷
        "\u{1F3B5}": "music",        // 🎵
        "\u{1F3B6}": "music",        // 🎶
        "\u{1F3E0}": "house",        // 🏠
        "\u{2B50}": "star",          // ⭐
        "\u{1F512}": "lock",         // 🔒
        "\u{1F4BC}": "briefcase",    // 💼
        "\u{1F4F0}": "article",      // 📰
        "\u{1F6D2}": "cart",         // 🛒
        "\u{1F30D}": "globe",        // 🌍
        "\u{1F527}": "gear",         // 🔧
        "\u{1F4D6}": "book",         // 📖
        "\u{1F4D5}": "book",         // 📕
        "\u{1F516}": "bookmark",     // 🔖
        "\u{1F4DD}": "note",         // 📝
        "\u{1F5D2}": "note",         // 🗒️
        "\u{1F4C5}": "calendar",     // 📅
        "\u{1F4C6}": "calendar",     // 📆
        "\u{2705}": "task",          // ✅
        "\u{1F4E6}": "package",      // 📦
        "\u{1F5C4}": "archive",      // 🗄️
        "\u{1F511}": "key",          // 🔑
        "\u{1F41B}": "bug",          // 🐛
        "\u{2699}": "gear",          // ⚙️
        "\u{1F6E0}": "gear",         // 🛠️
        "\u{1F4CD}": "pin",          // 📍
        "\u{1F30E}": "globe",        // 🌎
        "\u{1F30F}": "globe",        // 🌏
        "\u{1F3AB}": "ticket",       // 🎫
        "\u{1F9F3}": "bag",          // 🧳
        "\u{1F3E8}": "hotel",        // 🏨
        "\u{1F5FA}": "route",        // 🗺️
        "\u{1F464}": "person",       // 👤
        "\u{1F465}": "group",        // 👥
        "\u{1F4AC}": "chat",         // 💬
        "\u{2709}": "mail",          // ✉️
        "\u{1F4E7}": "mail",         // 📧
        "\u{1F4DE}": "call",         // 📞
        "\u{1F514}": "notify",       // 🔔
        "\u{25B6}": "play",          // ▶️
        "\u{1F3AC}": "film",         // 🎬
        "\u{1F3A5}": "video",        // 🎥
        "\u{1F4F9}": "video",        // 📹
        "\u{1F3A7}": "podcast",      // 🎧
        "\u{1F3A4}": "mic",          // 🎤
        "\u{1F5BC}": "photo",        // 🖼️
        "\u{1F4C8}": "levels",       // 📈
        "\u{1F4CA}": "levels",       // 📊
        "\u{1F3E1}": "house",        // 🏡
        "\u{1F331}": "plant",        // 🌱
        "\u{1F37D}": "food",         // 🍽️
        "\u{1F355}": "food",         // 🍕
        "\u{1FA7A}": "health",       // 🩺
        "\u{1F3CB}": "fitness",      // 🏋️
        "\u{1F436}": "pet",          // 🐶
        "\u{1F431}": "pet",          // 🐱
        "\u{1F697}": "car",          // 🚗
        "\u{2615}": "coffee",        // ☕
        "\u{2602}": "umbrella",      // ☂️
        "\u{1F9FA}": "laundry",      // 🧺
        "\u{1F3F3}": "flag",         // 🏳️
        "\u{1F6A9}": "flag",         // 🚩
        "\u{26A1}": "bolt",          // ⚡
        "\u{1F6E1}": "shield",       // 🛡️
        "\u{1F3AF}": "target",       // 🎯
        "\u{27A1}": "arrow",         // ➡️
        "\u{1F48E}": "diamond",      // 💎
        "\u{1F333}": "tree",         // 🌳
        "\u{26F0}": "mountain",      // ⛰️
        "\u{1F30A}": "wave",         // 🌊
        "\u{1F319}": "moon",         // 🌙
        "\u{2600}": "sun",           // ☀️
        "\u{1F343}": "leaf",         // 🍃
        "\u{1F525}": "fire",         // 🔥
        "\u{1F9EA}": "flask",        // 🧪
        "\u{1F4CF}": "ruler",        // 📏
        "\u{2702}": "scissors",      // ✂️
        "\u{231B}": "hourglass",     // ⌛
        "\u{1F3C5}": "medal",        // 🏅
        "\u{1F48A}": "pill",         // 💊
        "\u{1F3C6}": "trophy",       // 🏆
        "\u{1F5D1}": "trash",        // 🗑️
        "\u{1F504}": "sync",         // 🔄
        "\u{1F3F7}": "tag",          // 🏷️
        "\u{1F4B0}": "coin",         // 💰
        "\u{1F4B3}": "card",         // 💳
        "\u{1F9FE}": "receipt"       // 🧾
    ]
}

/// The four tints the icon set was drawn against, in the artwork's own order.
///
/// Deliberately four, not a colour picker: the set is one stroke weight and
/// one angle, and a folder that can be any colour stops reading as part of it.
/// Mint is the default because it is the set's own accent.
public enum ClearframeIconColor: String, CaseIterable, Sendable {
    case mint
    case grey
    case amber
    case blue

    /// Straight from the design's palette row.
    public var hex: String {
        switch self {
        case .mint: return "66DB7D"
        case .grey: return "8A8A94"
        case .amber: return "E9B04C"
        case .blue: return "5CA0F2"
        }
    }

    /// Red, green, and blue in 0...1, so the UI layer can build its own colour
    /// value without this file importing one.
    public var components: (red: Double, green: Double, blue: Double) {
        let value = UInt32(hex, radix: 16) ?? 0
        return (
            Double((value >> 16) & 0xFF) / 255,
            Double((value >> 8) & 0xFF) / 255,
            Double(value & 0xFF) / 255
        )
    }

    public var title: String {
        switch self {
        case .mint: return "Mint"
        case .grey: return "Grey"
        case .amber: return "Amber"
        case .blue: return "Blue"
        }
    }

    public init?(id: String?) {
        guard let id, let color = ClearframeIconColor(rawValue: id.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()) else {
            return nil
        }
        self = color
    }

    /// Keeps an unknown or blank stored value from shadowing the default.
    public static func normalizedID(_ value: String?) -> String? {
        ClearframeIconColor(id: value)?.rawValue
    }
}
