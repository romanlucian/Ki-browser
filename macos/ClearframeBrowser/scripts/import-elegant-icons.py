#!/usr/bin/env python3
"""Compile the licensed Elegant icon set into Swift catalog data.

The artwork is "Elegant" by Kenny Sing, GPL-3.0. Unlike the other licensed
sets this one is drawn entirely in `currentColor` with no strokes, so it is
tintable: a folder's chosen colour reaches it exactly as it reaches
Clearframe's own set. That is why it ships as a second line style rather than
another fixed-colour one.

GPL-3.0 is compatible with this repository's AGPL-3.0, and the combined work
stays under AGPL-3.0. Note what that costs: unlike artwork merely aggregated
under a Creative Commons licence, a GPL work compiled into the program brings
the whole program under copyleft, so the set has to be removed — or separately
licensed from its author — before any closed commercial terms could be offered.
That is a decision for the maintainer, recorded here so it is not discovered by
accident.

Every drawing is 32 units tall but the widths vary from 15 to 56, so each icon
carries its own box and the renderer preserves the aspect rather than stretching
anything to a square.

    python3 scripts/import-elegant-icons.py "~/Downloads/svg-icons (2)"

Rerun after replacing the artwork; never hand-edit the generated file.
"""
import re
import sys
import pathlib
import xml.etree.ElementTree as ET

PREFIX = "et--"

# Category order must match ClearframeIconCategory's declaration order.
CATEGORY_ORDER = [
    "work", "creative", "reading", "shopping", "travel", "code", "people",
    "media", "home", "markers", "nature", "objects", "interface",
    "faces", "food", "activities", "symbols", "flags",
]

# Every name in the set is filed by hand: a hundred is small enough to mean it,
# and an unmapped name is a hard error so replacing the artwork forces a
# decision rather than silently defaulting.
CATEGORIES = {
    "adjustments": "interface", "alarmclock": "work", "anchor": "travel",
    "aperture": "creative", "attachments": "work", "bargraph": "work",
    "basket": "shopping", "beaker": "code", "bike": "travel",
    "book-open": "reading", "briefcase": "work", "browser": "interface",
    "calendar": "work", "camera": "creative", "caution": "markers",
    "chat": "people", "circle-compass": "creative", "clipboard": "work",
    "clock": "work", "cloud": "code", "compass": "travel",
    "desktop": "objects", "dial": "interface", "document": "work",
    "documents": "work", "download": "interface", "dribbble": "media",
    "edit": "creative", "envelope": "work", "expand": "interface",
    "facebook": "media", "flag": "markers", "focus": "interface",
    "gears": "code", "genius": "creative", "gift": "shopping",
    "global": "travel", "globe": "travel", "googleplus": "media",
    "grid": "interface", "happy": "people", "hazardous": "markers",
    "heart": "markers", "hotairballoon": "travel", "hourglass": "work",
    "key": "interface", "laptop": "objects", "layers": "creative",
    "lifesaver": "markers", "lightbulb": "creative", "linegraph": "work",
    "linkedin": "media", "lock": "interface", "magnifying-glass": "interface",
    "map-pin": "markers", "map": "travel", "megaphone": "media",
    "mic": "media", "mobile": "objects", "newspaper": "reading",
    "notebook": "reading", "paintbrush": "creative", "paperclip": "work",
    "pencil": "creative", "phone": "people", "picture": "creative",
    "pictures": "creative", "piechart": "work", "presentation": "work",
    "pricetags": "shopping", "printer": "objects", "profile-female": "people",
    "profile-male": "people", "puzzle": "objects", "quote": "reading",
    "recycle": "nature", "refresh": "interface", "ribbon": "markers",
    "rss": "media", "sad": "people", "scissors": "objects",
    "scope": "interface", "search": "interface", "shield": "markers",
    "speedometer": "interface", "strategy": "work", "streetsign": "travel",
    "tablet": "objects", "telescope": "nature", "toolbox": "code",
    "tools-2": "code", "tools": "code", "traget": "markers",
    "trophy": "markers", "tumblr": "media", "twitter": "media",
    "upload": "interface", "video": "media", "wallet": "shopping",
    "wine": "food",
}


def inner_markup(path):
    raw = path.read_text()
    root = ET.fromstring(raw)
    box = root.attrib.get("viewBox", "").split()
    if len(box) != 4:
        raise SystemExit(f"{path.name}: unreadable viewBox")
    body = re.sub(r"^<svg[^>]*>", "", raw.strip(), count=1)
    body = re.sub(r"</svg>\s*$", "", body).strip()
    body = re.sub(r">\s+<", "><", body)
    if "currentColor" not in body:
        raise SystemExit(f"{path.name}: names a colour of its own; the tint would not reach it")
    return [float(v) for v in box], body


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

    grouped = {}
    for path in files:
        name = path.name[len(PREFIX):-len(".svg")]
        if name not in CATEGORIES:
            raise SystemExit(f"{name}: no category assigned — add one to CATEGORIES")
        box, body = inner_markup(path)
        grouped.setdefault(CATEGORIES[name], []).append((f"elegant-{name}", box, body))

    rows = []
    for category in CATEGORY_ORDER:
        for icon_id, box, body in grouped.get(category, []):
            rows.append(
                f'        icon("{icon_id}", .{category}, '
                f"{box[0]:g}, {box[1]:g}, {box[2]:g}, {box[3]:g},\n"
                f"             {swift_literal(body)})"
            )

    text = "\n".join([
        "import Foundation",
        "",
        "/// The licensed Elegant icon set, compiled in like every other shipped",
        "/// list. Nothing here is fetched or replaced at runtime.",
        "///",
        "/// Artwork: \"Elegant\" by Kenny Sing, GPL-3.0. Drawn entirely in",
        "/// `currentColor`, which is what makes it the second tintable set: a",
        "/// folder's colour reaches it the same way it reaches Clearframe's own.",
        "///",
        "/// GPL-3.0 is compatible with this repository's AGPL-3.0 and the combined",
        "/// work stays AGPL-3.0. It is copyleft over the whole program though, not",
        "/// merely over adaptations of the artwork, so this set would have to go —",
        "/// or be separately licensed from its author — before any closed",
        "/// commercial terms could be offered.",
        "///",
        "/// Widths vary from 15 to 56 against a fixed height of 32, so each icon",
        "/// carries its own box and nothing is stretched to a square.",
        "///",
        "/// Generated by scripts/import-elegant-icons.py. Edit the artwork and",
        "/// rerun it; never edit this file by hand.",
        "enum ElegantIconCatalogData {",
        "    static let icons: [ClearframeIcon] = [",
        ",\n".join(rows),
        "    ]",
        "",
        "    private static func icon(",
        "        _ id: String,",
        "        _ category: ClearframeIconCategory,",
        "        _ x: Double,",
        "        _ y: Double,",
        "        _ width: Double,",
        "        _ height: Double,",
        "        _ markup: String",
        "    ) -> ClearframeIcon {",
        "        ClearframeIcon(",
        "            id: id,",
        "            category: category,",
        "            markup: markup,",
        "            style: .elegant,",
        "            box: VectorBox(x: x, y: y, width: width, height: height)",
        "        )",
        "    }",
        "}",
        "",
    ])

    destination = (
        pathlib.Path(__file__).resolve().parent.parent
        / "Sources/ClearframeCore/ElegantIconCatalogData.swift"
    )
    destination.write_text(text)
    counts = {}
    for category, entries in grouped.items():
        counts[category] = len(entries)
    print(f"wrote {sum(counts.values())} icons to {destination}")
    for category in CATEGORY_ORDER:
        if category in counts:
            print(f"  {category:<12} {counts[category]}")


if __name__ == "__main__":
    main()
