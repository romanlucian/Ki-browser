#!/usr/bin/env python3
"""Compile the licensed Stickies icon sets into Swift catalog data.

The artwork is Streamline's "Stickies color icons", CC BY 4.0. Each source
file is one icon in one of two styles — a plain form and a `-duo` form with a
hard offset shadow — so 200 files are 100 drawings twice, and the two ship as
two selectable styles rather than one mixed set.

Markup is stored the way the Clearframe set is: verbatim, minus the `<svg>`
wrapper, with the wrapper's `viewBox` lifted onto the icon so the renderer is
told the box rather than assuming one. Groups, `<defs>`, and `<use>` are left
intact; `VectorPathParser` resolves them.

    python3 scripts/import-stickies-icons.py ~/Downloads/svg-icons

Rerun this after replacing the artwork; never hand-edit the generated file.
"""
import re
import sys
import pathlib
import xml.etree.ElementTree as ET

PREFIX = "streamline-stickies-color--"
NS = "{http://www.w3.org/2000/svg}"

# Which picker section each drawing belongs in. Every name in the set must
# appear here: an unmapped icon is a hard error, not a silent "objects", so
# that replacing the artwork forces a deliberate decision about each one.
CATEGORIES = {
    "3d": "creative", "add-device": "interface", "airport-railroad": "travel",
    "android-setting": "interface", "app-window": "interface",
    "astrology-study": "nature", "baby-cart-quality": "people", "baby": "people",
    "backpack": "travel", "balloon-tour": "travel", "bigben": "travel",
    "bluetooth": "interface", "boarding-pass": "travel", "book-library": "reading",
    "bug": "code", "bus-route-info": "travel", "cancel-2": "interface",
    "candy-cane": "objects", "checking-order": "shopping",
    "cloud-data-transfer": "code", "coding": "code", "compass-1": "travel",
    "construction-area": "objects", "control": "interface", "cursor": "interface",
    "dangerous-chemical-lab": "objects", "date-time-setting": "work",
    "drawer-inbox": "work", "drone": "objects", "earpod-connected": "media",
    "easter-egg": "objects", "education-degree": "reading", "eiffel-tower": "travel",
    "elevator-lift": "objects", "face-id-1": "interface", "filming-movie": "media",
    "ghost": "objects", "gift-reciept": "shopping", "globe-1": "travel",
    "graph-bar": "work", "graph-pie": "work", "guitar-amplifier": "media",
    "help": "interface", "information-toilet-location": "markers",
    "instruments-piano": "media", "key": "interface",
    "keyboard-direction": "interface", "lab-tools": "objects", "labtop": "work",
    "library-research": "reading", "love": "markers", "mail": "work",
    "mailbox-2": "work", "medal": "markers", "mobile-phone": "objects",
    "money-briefcase": "shopping", "money-coin-2": "shopping", "muslim": "people",
    "nuclear-2": "objects", "on-off-1": "interface", "online-information": "interface",
    "passport": "travel", "pen": "creative", "photography": "creative",
    "picture": "creative", "pile-of-money": "shopping", "plant-1": "nature",
    "product-cloth": "shopping", "programming": "code", "qr-code": "interface",
    "reciept-1": "shopping", "recycle": "nature", "refund-product-reciept": "shopping",
    "reward": "markers", "rocket-launch-chart": "work", "sad-song": "media",
    "safety": "interface", "school": "reading", "science-lab": "objects",
    "search": "interface", "sent-from-computer": "work", "server-network": "code",
    "shop-store": "shopping", "slate": "reading", "smart-tv": "media",
    "snowman": "nature", "solar-power-battery": "objects", "star": "markers",
    "sun-clound-weather": "nature", "sun": "nature", "taxi": "travel",
    "telescope": "nature", "time": "work", "validation-1": "interface",
    "view-mail": "work", "vr-goggle": "media", "wand": "creative",
    "winter-day-activities": "nature", "world-nature": "nature", "wrench": "objects",
}

# Category order must match ClearframeIconCategory's declaration order, which
# is the order the picker shows.
CATEGORY_ORDER = [
    "work", "creative", "reading", "shopping", "travel", "code", "people",
    "media", "home", "markers", "nature", "objects", "interface",
]

# Attributes the renderer does not read. `stroke-miterlimit` is dropped because
# the artwork's value of 10 is already what the renderer uses; `clip-rule` only
# applies to clip paths, and every clip in this set is the icon's own frame.
# `stroke-linecap` and `stroke-linejoin` are deliberately NOT dropped: without
# them a star's points come out rounded instead of sharp.
DROPPED = ("stroke-miterlimit", "clip-rule")


def inner_markup(path):
    """The `<svg>` element's contents, minified, with the viewBox lifted off."""
    raw = path.read_text()
    root = ET.fromstring(raw)
    view_box = root.attrib["viewBox"].split()
    if len(view_box) != 4:
        raise SystemExit(f"{path.name}: unreadable viewBox")

    body = re.sub(r"^<svg[^>]*>", "", raw.strip(), count=1)
    body = re.sub(r"</svg>\s*$", "", body).strip()
    body = re.sub(r">\s+<", "><", body)
    for attribute in DROPPED:
        body = re.sub(rf'\s{attribute}="[^"]*"', "", body)
    # The parser reads `href`; the namespaced alias never appears in this set,
    # but refuse rather than silently drop it if the artwork ever changes.
    if "xlink" in body:
        raise SystemExit(f"{path.name}: xlink:href is not supported")
    return [float(v) for v in view_box], body


def swift_literal(text):
    """A raw Swift string literal, with enough hashes to survive the content."""
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

    styles = {"stickiesPlain": {}, "stickiesDuo": {}}
    for path in files:
        name = path.name[len(PREFIX):-len(".svg")]
        style = "stickiesDuo" if name.endswith("-duo") else "stickiesPlain"
        base = name[:-len("-duo")] if style == "stickiesDuo" else name
        if base not in CATEGORIES:
            raise SystemExit(f"{base}: no category assigned — add one to CATEGORIES")
        box, body = inner_markup(path)
        slug = "stickies-duo-" if style == "stickiesDuo" else "stickies-"
        styles[style].setdefault(CATEGORIES[base], []).append(
            (slug + base, base, box, body)
        )

    out = [
        "import Foundation",
        "",
        "/// The licensed Stickies icon sets, compiled in the same way as every",
        "/// other shipped list: reviewed, tested, and built into the binary.",
        "/// Nothing here is fetched or replaced at runtime.",
        "///",
        "/// Artwork: \"Stickies color icons\" by Streamline, CC BY 4.0",
        "/// (https://creativecommons.org/licenses/by/4.0/). One hundred drawings",
        "/// in two styles — plain, and `duo` with a hard offset shadow. Unlike the",
        "/// Clearframe set these carry their own colours, so a folder tint has",
        "/// nothing to act on; that is the artwork's nature, not a missing feature.",
        "///",
        "/// Generated by scripts/import-stickies-icons.py. Edit the artwork and",
        "/// rerun it; never edit this file by hand.",
        "enum StickiesIconCatalogData {",
        "    static let icons: [ClearframeIcon] = plain + duo",
        "",
    ]

    total = 0
    for style, member in (("stickiesPlain", "plain"), ("stickiesDuo", "duo")):
        out.append(f"    static let {member}: [ClearframeIcon] = [")
        rows = []
        for category in CATEGORY_ORDER:
            for icon_id, base, box, body in styles[style].get(category, []):
                total += 1
                rows.append(
                    f'        icon("{icon_id}", .{category}, .{style}, '
                    f"{box[0]:g}, {box[1]:g}, {box[2]:g}, {box[3]:g},\n"
                    f"             {swift_literal(body)})"
                )
        out.append(",\n".join(rows))
        out.append("    ]")
        out.append("")

    out += [
        "    private static func icon(",
        "        _ id: String,",
        "        _ category: ClearframeIconCategory,",
        "        _ style: ClearframeIconStyle,",
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
        "            style: style,",
        "            box: VectorBox(x: x, y: y, width: width, height: height)",
        "        )",
        "    }",
        "}",
        "",
    ]

    destination = (
        pathlib.Path(__file__).resolve().parent.parent
        / "Sources/ClearframeCore/StickiesIconCatalogData.swift"
    )
    destination.write_text("\n".join(out))
    print(f"wrote {total} icons to {destination}")


if __name__ == "__main__":
    main()
