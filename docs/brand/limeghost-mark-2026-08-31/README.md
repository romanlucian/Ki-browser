# Limeghost mark — August 31, 2026

Three files, one system. They are not alternatives: each has a place, and using
the wrong one is what makes a brand look careless.

| File | Size | Where it belongs |
|---|---|---|
| `limeghost-mark-full.png` | 1254 × 1254 | App icon, Dock, website header, App Store. Anywhere at 32 px or larger. |
| `limeghost-mark-small.png` | 1254 × 1254 | The 16 px favicon, the tab, the menu bar. The owl's face alone — no ring, no wing. |
| `limeghost-mark-mono.png` | 1271 × 1238 | One-colour contexts: print, watermarks, a stamp. Black on transparent; recolour as needed. |

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

## Settled since

`macos/LimeghostBrowser/scripts/generate-app-icon.swift` reads the full and
small marks and switches between them by size, so this **is** the app icon. It
replaced a procedural cut-corner frame that shared its geometry with the 104
folder icons; ending that family relationship, and giving up the script's
automatic small-size weight compensation, was a deliberate trade. A missing
artwork file warns and falls back to the old geometric mark rather than
breaking the build.

## Open

- **Not vector.** These are PNG. Fine for the app icon, which never needs more
  than 1024 px, but the website and print will want an SVG. Tracing is the cheap
  route; redrawing is the honest one.
- **The ring is not a true circle.** It is slightly irregular — thicker at the
  lower left, flatter at the upper right. Invisible at icon sizes, visible at
  1024 px. Fix it when the mark is redrawn as vector.
- **The wordmark still has to be redrawn.** These sheets were made while the
  product was called Clearframe. The name is **Limeghost** as of the same day —
  see [../naming-decision-2026-08-31.md](../naming-decision-2026-08-31.md) — so
  every lockup that pairs the symbol with a wordmark needs setting again.
