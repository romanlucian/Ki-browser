#!/usr/bin/env python3
"""Compile the licensed EmojiOne set into Swift catalog data.

The artwork is EmojiOne v1, CC BY-SA 4.0 — a share-alike licence, unlike the
CC BY of the Stickies sets. Attribution is required, and any modification of
the artwork itself must be shared under the same terms. Bundling the set in an
application is a collection rather than an adaptation, and CC 4.0 states that a
change of format alone never creates an adaptation, so this conversion does not
put the application under share-alike. Keep it that way: do not redraw these
icons in place, and do not merge them with Limeghost's own set.

Every drawing sits in a 64-unit box, so the box is written once rather than per
icon. Coordinates are stored verbatim. Rounding them looked tempting — it saves
about a fifth of the bytes — but this artwork is drawn almost entirely in
relative commands, so any rounding accumulates along a path rather than
cancelling out, and the set is full of deltas smaller than the rounding step.
The compiler handles the full data in seconds once it is split, so there is
nothing to buy.

    python3 scripts/import-emojione-icons.py "~/Downloads/svg-icons (1)"

Rerun after replacing the artwork; never hand-edit the generated files.
"""
import re
import sys
import pathlib
import xml.etree.ElementTree as ET

PREFIX = "emojione-v1--"
NS = "{http://www.w3.org/2000/svg}"
# Splitting the set keeps any one file a reasonable size for the compiler and
# lets it build the pieces in parallel.
CHUNKS = 8

# Category order must match LimeghostIconCategory's declaration order.
CATEGORY_ORDER = [
    "work", "creative", "reading", "shopping", "travel", "code", "people",
    "media", "home", "markers", "nature", "objects", "interface",
    "faces", "food", "activities", "symbols", "flags",
]

# Heuristic filing, checked in this order, first match wins. Twelve hundred
# emoji cannot be filed by hand, and search is what people actually use here —
# categories only exist so the grid is not one undifferentiated wall. Anything
# unmatched lands in Objects, which is honest for a set that is mostly things.
RULES = [
    ("flags", ["flag"]),
    ("faces", [
        "face", "smiley", "grin", "expressionless", "sleepy", "tired", "weary",
        "pensive", "confused", "worried", "frowning", "anguished", "astonished",
        "flushed", "dizzy", "hushed", "disappointed", "persevering", "unamused",
        "crying", "joy", "relieved", "smirking", "kissing", "winking", "neutral",
        "imp", "ghost", "skull", "alien", "japanese-ogre", "japanese-goblin",
        "clown", "poo", "robot",
    ]),
    ("nature", [
        "cat", "dog", "mouse", "hamster", "rabbit", "bear", "panda", "koala",
        "tiger", "lion", "cow", "pig", "frog", "monkey", "chicken", "penguin",
        "bird", "wolf", "boar", "horse", "unicorn", "bee", "bug", "butterfly",
        "snail", "beetle", "ant", "spider", "scorpion", "crab", "snake",
        "turtle", "tropical-fish", "fish", "dolphin", "whale", "shark",
        "octopus", "shell", "crocodile", "leopard", "camel", "elephant",
        "rhinoceros", "goat", "ram", "sheep", "rooster", "turkey", "dove",
        "poodle", "paw", "dragon", "flower", "blossom", "rose", "hibiscus",
        "sunflower", "tulip", "seedling", "evergreen", "deciduous", "palm-tree",
        "cactus", "herb", "shamrock", "clover", "maple-leaf", "leaf", "mushroom",
        "chestnut", "sun", "moon", "star", "cloud", "rain", "snow", "thunder",
        "lightning", "tornado", "fog", "wind", "rainbow", "umbrella", "droplet",
        "wave", "volcano", "mountain", "desert", "beach", "globe", "earth",
        "water-buffalo", "ox", "mouse-", "rat", "bat", "duck", "owl", "eagle",
        "squid", "shrimp", "lobster", "seal", "otter", "sloth", "llama",
        "giraffe", "zebra", "hedgehog", "kangaroo", "badger", "swan", "flamingo",
        "peacock", "parrot", "lizard", "dinosaur", "sauropod",
    ]),
    ("food", [
        "apple", "banana", "grape", "melon", "watermelon", "tangerine", "lemon",
        "pineapple", "cherries", "strawberry", "peach", "pear", "kiwi", "mango",
        "coconut", "avocado", "tomato", "eggplant", "aubergine", "carrot",
        "corn", "pepper", "cucumber", "potato", "bread", "croissant", "baguette",
        "pretzel", "cheese", "meat", "bacon", "hamburger", "fries", "pizza",
        "hotdog", "hot-dog", "sandwich", "taco", "burrito", "egg", "cooking",
        "pot-of-food", "stew", "bowl", "spaghetti", "ramen", "sushi", "bento",
        "curry", "rice", "dango", "oden", "fish-cake", "shaved-ice", "ice-cream",
        "doughnut", "cookie", "cake", "pie", "chocolate", "candy", "lollipop",
        "custard", "honey", "milk", "coffee", "tea", "sake", "wine", "cocktail",
        "beer", "champagne", "whisky", "cup", "fork", "knife", "spoon", "plate",
        "chopsticks", "takeout", "dumpling", "popcorn", "salad", "soft-ice",
        "roasted", "poultry", "french", "steaming", "shortcake", "birthday-cake",
        "beverage", "drink", "juice", "bottle", "peanuts", "pancakes", "waffle",
    ]),
    ("people", [
        "person", "boy", "girl", "man", "woman", "baby", "family", "couple",
        "dancer", "police", "worker", "guard", "detective", "santa", "angel",
        "princess", "bride", "prince", "student", "teacher", "farmer", "cook",
        "mechanic", "scientist", "artist", "pilot", "astronaut", "judge",
        "haircut", "massage", "walking", "running", "bow", "ok-gesture",
        "no-gesture", "raising", "shrug", "gesture", "hand", "thumbs", "clap",
        "wave", "fist", "victory", "point", "finger", "muscle", "pray", "nail",
        "ear", "nose", "eye", "mouth", "tongue", "lips", "footprint", "speaking",
        "silhouette", "bust", "adult", "older", "elder", "twins", "kiss",
        "sleeping-accommodation", "bath", "toilet", "shower", "selfie",
    ]),
    ("activities", [
        "soccer", "football", "basketball", "baseball", "tennis", "volleyball",
        "rugby", "golf", "bowling", "cricket", "hockey", "badminton", "boxing",
        "martial", "goal", "ski", "snowboard", "skate", "sled", "curling",
        "swim", "surf", "row", "bike", "bicycl", "climb", "lifting", "fencing",
        "medal", "trophy", "ticket", "circus", "performing", "art", "video-game",
        "joystick", "dart", "billiards", "crystal-ball", "slot", "bowling",
        "game-die", "puzzle", "teddy", "kite", "yo-yo", "party", "confetti",
        "balloon", "ribbon", "gift", "firework", "sparkler", "carousel",
        "ferris", "roller-coaster", "fishing", "camping", "tent",
    ]),
    ("travel", [
        "airplane", "helicopter", "rocket", "satellite", "seat", "car",
        "taxi", "bus", "trolleybus", "tram", "train", "railway", "metro",
        "monorail", "tractor", "truck", "lorry", "ambulance", "fire-engine",
        "police-car", "motorcycle", "motor-scooter", "scooter", "bicycle",
        "ship", "boat", "canoe", "ferry", "sailboat", "speedboat", "anchor",
        "fuel", "station", "traffic", "construction", "bridge", "map", "compass",
        "luggage", "suitcase", "passport", "customs", "baggage", "aerial",
        "mountain-railway", "cable-car", "tramway", "house", "hotel", "school",
        "office", "post-office", "hospital", "bank", "convenience", "store",
        "factory", "castle", "church", "mosque", "synagogue", "temple", "kaaba",
        "stadium", "statue", "tokyo", "fountain", "sunrise", "sunset",
        "cityscape", "night-with-stars", "milky-way", "bridge-at-night",
        "foggy", "japan", "world-map", "moai", "elevator", "wheel",
    ]),
    ("media", [
        "camera", "video", "film", "movie", "projector", "clapper", "television",
        "radio", "microphone", "headphone", "speaker", "sound", "musical",
        "music", "note", "guitar", "trumpet", "saxophone", "violin", "drum",
        "banjo", "accordion", "level-slider", "control-knobs", "studio",
        "satellite-antenna", "dvd", "cd", "minidisc", "floppy", "vhs",
        "cassette", "mobile-phone", "telephone", "pager", "fax", "antenna",
    ]),
    ("work", [
        "briefcase", "chart", "graph", "calendar", "clipboard", "file", "folder",
        "card-index", "ledger", "notebook", "memo", "pencil", "pen", "paperclip",
        "pushpin", "straight-ruler", "triangular-ruler", "scissors", "printer",
        "computer", "laptop", "keyboard", "desktop", "abacus", "balance",
        "date", "spiral", "bookmark-tabs", "page", "newspaper", "receipt",
        "money", "dollar", "euro", "pound", "yen", "credit-card", "chart-",
        "wastebasket", "trash", "envelope", "mail", "inbox", "outbox", "package",
        "postbox", "e-mail", "incoming", "clock", "watch", "hourglass", "timer",
        "alarm", "stopwatch",
    ]),
    ("reading", [
        "book", "books", "library", "scroll", "graduation", "school-satchel",
        "closed-book", "open-book", "orange-book", "blue-book", "green-book",
        "notebook-with", "label",
    ]),
    ("markers", [
        "heart", "love", "sparkle", "star-", "glowing", "collision", "anger",
        "boom", "dizzy-symbol", "sweat-droplets", "dash", "hole", "bomb",
        "speech", "thought", "balloon-", "zzz", "hundred", "exclamation",
        "question", "warning",
    ]),
    ("symbols", [
        "arrow", "sign", "button", "symbol", "zodiac", "aries", "taurus",
        "gemini", "cancer", "leo", "virgo", "libra", "scorpius", "sagittarius",
        "capricorn", "aquarius", "pisces", "ophiuchus", "recycl", "trident",
        "fleur", "circle", "square", "diamond", "triangle", "curly", "loop",
        "check", "cross", "multiplication", "plus", "minus", "division",
        "infinity", "copyright", "registered", "trade-mark", "keycap", "digit",
        "number", "asterisk", "hash", "letter", "input", "wheelchair",
        "restroom", "water-closet", "passport-control", "left", "right", "up",
        "down", "back", "end", "on-", "soon", "top", "clockwise", "anticlockwise",
        "radioactive", "biohazard", "peace", "cross-mark", "om", "wheel-of",
        "star-and-crescent", "menorah", "yin", "orthodox", "place-of-worship",
        "atom", "medical", "no-entry", "prohibited", "children-crossing",
        "currency", "atm", "litter", "potable", "non-potable", "bicycle-sign",
        "mobile-phone-off", "vibration", "eight", "sparkle-", "eject", "play",
        "pause", "stop-button", "record", "next", "previous", "shuffle", "repeat",
    ]),
    ("home", [
        "bed", "couch", "door", "window", "lamp", "candle", "bath", "shower",
        "bathtub", "toilet", "soap", "sponge", "broom", "basket", "thread",
        "sewing", "yarn", "chair", "mirror", "plunger", "bucket", "key",
        "lock", "unlock", "hook", "ladder", "mouse-trap",
    ]),
    ("creative", [
        "paint", "artist-palette", "palette", "crayon", "framed", "picture",
        "performing-arts", "thread-", "ring", "gem", "crown", "lipstick",
        "kimono", "dress", "shirt", "jeans", "necktie", "coat", "scarf",
        "gloves", "socks", "shoe", "boot", "sandal", "hat", "helmet", "glasses",
        "goggles", "purse", "handbag", "pouch", "backpack", "umbrella-",
    ]),
    ("code", [
        "computer-disk", "abacus-", "gear", "nut-and-bolt", "wrench", "hammer",
        "screwdriver", "toolbox", "chains", "magnet", "battery", "electric",
        "bulb", "flashlight", "telescope", "microscope", "test-tube",
        "petri", "dna", "satellite-", "link", "electric-plug",
    ]),
]


def category_for(name):
    for category, keywords in RULES:
        if any(k in name for k in keywords):
            return category
    return "objects"


def inner_markup(path):
    raw = path.read_text()
    root = ET.fromstring(raw)
    if root.attrib.get("viewBox") != "0 0 64 64":
        raise SystemExit(f"{path.name}: unexpected viewBox {root.attrib.get('viewBox')!r}")
    body = re.sub(r"^<svg[^>]*>", "", raw.strip(), count=1)
    body = re.sub(r"</svg>\s*$", "", body).strip()
    body = re.sub(r">\s+<", "><", body)
    body = re.sub(r"<!--.*?-->", "", body, flags=re.S)
    return body


def swift_literal(text):
    hashes = "#"
    while hashes + '"' in text or '"' + hashes in text:
        hashes += "#"
    return f'{hashes}"{text}"{hashes}'


def main():
    if len(sys.argv) != 2:
        raise SystemExit(__doc__)
    source = pathlib.Path(sys.argv[1]).expanduser()
    files = sorted(source.glob(f"{PREFIX}*.svg"))
    if not files:
        raise SystemExit(f"no {PREFIX}*.svg under {source}")

    entries, skipped = [], []
    for path in files:
        name = path.name[len(PREFIX):-len(".svg")]
        body = inner_markup(path)
        # One icon in the set is painted with a radial gradient, which this
        # renderer has no way to draw. Skipping it is honest; approximating a
        # flag with a flat colour would not be.
        if "Gradient" in body:
            skipped.append(name)
            continue
        entries.append((f"emoji-{name}", category_for(name), body))

    entries.sort(key=lambda e: (CATEGORY_ORDER.index(e[1]), e[0]))

    destination = pathlib.Path(__file__).resolve().parent.parent / "Sources/LimeghostCore"
    for old in destination.glob("EmojiOneIconCatalogData*.swift"):
        old.unlink()

    size = -(-len(entries) // CHUNKS)
    parts = [entries[i:i + size] for i in range(0, len(entries), size)]

    for index, part in enumerate(parts):
        rows = ",\n".join(
            f'        icon("{icon_id}", .{category},\n             {swift_literal(body)})'
            for icon_id, category, body in part
        )
        text = "\n".join([
            "import Foundation",
            "",
            f"/// EmojiOne artwork, part {index + 1} of {len(parts)}. See",
            "/// `EmojiOneIconCatalogData` for the licence and the generator.",
            f"enum EmojiOneIconCatalogData{index} {{",
            "    static let icons: [LimeghostIcon] = [",
            rows,
            "    ]",
            "",
            "    private static func icon(",
            "        _ id: String,",
            "        _ category: LimeghostIconCategory,",
            "        _ markup: String",
            "    ) -> LimeghostIcon {",
            "        LimeghostIcon(",
            "            id: id,",
            "            category: category,",
            "            markup: markup,",
            "            style: .emojiOne,",
            "            box: VectorBox(x: 0, y: 0, width: 64, height: 64)",
            "        )",
            "    }",
            "}",
            "",
        ])
        (destination / f"EmojiOneIconCatalogData{index}.swift").write_text(text)

    joined = " + ".join(f"EmojiOneIconCatalogData{i}.icons" for i in range(len(parts)))
    index_text = "\n".join([
        "import Foundation",
        "",
        "/// The licensed EmojiOne set, compiled in like every other shipped list.",
        "/// Nothing here is fetched or replaced at runtime.",
        "///",
        '/// Artwork: EmojiOne v1 by Emoji One, CC BY-SA 4.0',
        "/// (https://creativecommons.org/licenses/by-sa/4.0/). Share-alike: the",
        "/// artwork may be redistributed and used commercially with attribution,",
        "/// and any modification of the artwork itself must be shared under the",
        "/// same licence. Bundling it is a collection rather than an adaptation,",
        "/// and a change of format alone never creates one, so this does not put",
        "/// the application under share-alike — but redrawing these icons in",
        "/// place would.",
        "///",
        "/// Split across files only so the compiler can build the set in",
        "/// parallel. Generated by scripts/import-emojione-icons.py; edit the",
        "/// artwork and rerun it rather than editing these files.",
        "enum EmojiOneIconCatalogData {",
        f"    static let icons: [LimeghostIcon] = {joined}",
        "}",
        "",
    ])
    (destination / "EmojiOneIconCatalogData.swift").write_text(index_text)

    counts = {}
    for _, category, _ in entries:
        counts[category] = counts.get(category, 0) + 1
    print(f"wrote {len(entries)} icons across {len(parts)} files")
    if skipped:
        print(f"skipped (gradient artwork this renderer cannot draw): {', '.join(skipped)}")
    for category in CATEGORY_ORDER:
        if category in counts:
            print(f"  {category:<12} {counts[category]}")


if __name__ == "__main__":
    main()
