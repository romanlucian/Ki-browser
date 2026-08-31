# Clearframe mark — August 31, 2026

Three files, one system. They are not alternatives: each has a place, and using
the wrong one is what makes a brand look careless.

| File | Size | Where it belongs |
|---|---|---|
| `clearframe-mark-full.png` | 1254 × 1254 | App icon, Dock, website header, App Store. Anywhere at 32 px or larger. |
| `clearframe-mark-small.png` | 1254 × 1254 | The 16 px favicon, the tab, the menu bar. The owl's face alone — no ring, no wing. |
| `clearframe-mark-mono.png` | 1271 × 1238 | One-colour contexts: print, watermarks, a stamp. Black on transparent; recolour as needed. |

## What was verified, and how

- **The transparency is real.** All three carry a true alpha channel — corner
  alpha is 0 and roughly 60 percent of each canvas is fully clear. Checked by
  sampling pixels, not by looking at a checkerboard, because generators
  routinely paint a fake one.
- **The cut-out is clean.** Composited onto white and onto magenta: no white
  fringe, no halo, and the eye notches are crisp. Magenta is the harsh test;
  fringing is invisible against white and against black.
- **It survives its sizes.** The full mark was rendered at 32 px on Clearframe's
  own near-black and still reads as ring, face and wing. The small mark was
  rendered at 16 px and still reads as a heart with two eyes — which is the
  whole reason it exists.
- **The mono mark carries its form in negative space** — the gaps between wing
  sweeps, the eye notches, the ring's inner edge. That is why it survives with
  no colour at all. An earlier attempt at a flat version failed precisely
  because the drawing defined its shape with value instead, and flattening it
  produced a solid blob.

## The rule that produced these

The gradient must never approach the background. It runs roughly `#8FF0A8` to
`#1B7A3C` and stops there. An earlier version faded to near-black, which looked
striking on a dark presentation and lost the owl's whole body on Clearframe's
own near-black chrome — the face floated above a wing with nothing joining them.
Firefox's mark is the reference: fifteen years and four redesigns spent
*removing detail* while keeping the gradient, and its palette never touches
white or black.

## Open

- **Not vector.** These are PNG. Fine for the app icon, which never needs more
  than 1024 px, but the website and print will want an SVG. Tracing is the cheap
  route; redrawing is the honest one.
- **The ring is not a true circle.** It is slightly irregular — thicker at the
  lower left, flatter at the upper right. Invisible at icon sizes, visible at
  1024 px. Fix it when the mark is redrawn as vector.
- **The name's casing is unsettled.** The codebase says `Clearframe` (1,151
  occurrences, zero of `ClearFrame`); early logo sheets said `ClearFrame`.
  Whatever is chosen governs the wordmark, the domain and the App Store listing.
- **Not yet the app icon.** `macos/ClearframeBrowser/scripts/generate-app-icon.swift`
  still draws the icon procedurally — a cut-corner frame sharing its geometry
  with the 104 folder icons. Adopting the owl replaces that and ends the family
  relationship, and gives up the automatic small-size weight compensation the
  script performs. That is a real trade, and it has not been made.
