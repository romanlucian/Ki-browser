# Intellectual property and ownership

**Status:** August 20, 2026. Maintained as an accurate ownership record, not a marketing document. If any statement here stops being true, correct it the same day.

**Purpose.** A single place that answers "who owns this, what is in it, and can it be transferred or licensed commercially." Written now, while the answers are simple, rather than under the pressure of a transaction or an investor's diligence request.

> This file is a factual record assembled from the repository. It is not legal advice. The items marked **Needs professional advice** require a qualified lawyer in the relevant jurisdiction before anyone relies on them.

## 1. Ownership summary

| | |
|---|---|
| Author and copyright holder | **Lucian Roman** |
| Trading identity | **Zincoo** — zincoo.com — credited in the app as "Limeghost by Zincoo" |
| Product | Limeghost, a standalone macOS browser |
| Repository | `github.com/romanlucian/Ki-browser` |
| Licence | AGPL-3.0-only, verbatim upstream text in `LICENSE`, declared as `AGPL-3.0-only` in `package.json` |
| Outside contributors | **None** |

**Needs confirmation by the founder** (only he can answer these, and a buyer or investor will ask):

- Whether Zincoo is a registered legal entity, and if so its jurisdiction, registration number, and whether the copyright sits with the entity or with Lucian Roman personally. This determines who signs a transfer.
- Whether any part of this work was produced during employment or under a contract containing an IP-assignment clause. This is the most common way authorship becomes disputed after the fact.
- Whether any third party has ever been paid or engaged for design, code, or assets on this project.

## 2. Contribution history

Verifiable from the repository as of August 20, 2026:

- Every commit in the history carries a single author: `romanlucian`.
- `.github/CODEOWNERS` assigns the whole tree (`*`) to `@romanlucian`.
- No pull request from an outside party has been merged.
- `AGENTS.md` records that contribution terms — a CLA or DCO — remain deliberately undecided, and that accepting outside patches before that is settled would compromise the ability to offer separate commercial terms.

**Why this matters more than it looks.** AGPL-3.0 is a copyleft licence, but the copyright holder is not bound by his own licence. Because Lucian Roman owns 100% of the copyright, he can license the identical code to a commercial buyer on entirely different terms, including proprietary ones. That option exists **only while sole ownership holds**.

The first outside contribution merged without a signed contributor agreement creates a co-owner who can refuse to relicense. That single event would remove the ability to sell clean commercial rights. Keep the current policy until a contributor agreement is deliberately adopted.

## 3. Software dependencies

**Limeghost has no third-party code dependencies.** Verified: `macos/LimeghostBrowser/Package.swift` declares only internal target dependencies (`LimeghostCore`, `LimeghostBrowser`), and `package.json` declares no runtime or development packages. There is no `node_modules`, no vendored library, no package manager pulling external source into a build.

This is unusual and worth stating plainly to any reviewer: there is no transitive licence exposure, no supply-chain inheritance, and no dependency whose terms could change under a new owner.

What the app does use:

- **Apple system frameworks** — WebKit, AppKit, SwiftUI, Foundation, Security, AVFoundation, Speech. Used under the Apple SDK licence that governs any macOS application. No redistribution obligation.
- **The CEF scaffold** at `chromium/cef-spike` — an isolated architecture validation containing Limeghost's own Objective-C header and CMake configuration. **No Chromium or CEF source or binary is committed to this repository.** It is not linked into the shipping app. If a future Chromium migration proceeds, CEF's own licence terms (BSD-style, plus Chromium's own components) become relevant and must be reviewed then.

## 4. Bundled assets and their obligations

Three folder-icon sets ship inside the app. Their terms survive a sale and bind any future owner.

| Set | Count | Source and licence | Obligation |
|---|---|---|---|
| **Limeghost** | 104 | Original work, authored for this project | None. Owned outright. The only tintable set — drawn in `currentColor`. |
| **Stickies** | 100 | Streamline, **CC BY 4.0** | Attribution required and must remain visible. Rendered in the folder picker as "Stickies by Streamline, CC BY 4.0". |
| **EmojiOne v1** | 1,261 | Emoji One, **CC BY-SA 4.0** | Attribution required *and* share-alike. Rendered as "EmojiOne v1 by Emoji One, CC BY-SA 4.0". |

**The EmojiOne share-alike boundary is the important one.** Bundling the artwork alongside the app is a *collection*, which does not place the application under share-alike. **Modifying that artwork would create an adaptation, which would.** The codebase treats it as read-only for exactly this reason: `EmojiOneIconCatalogData*.swift` is generated by `scripts/import-emojione-icons.py` and must be regenerated rather than hand-edited, and it must never be merged into Limeghost's own set. A future owner who edits those files could put their own product under CC BY-SA. This constraint is recorded in `CLAUDE.md` so it survives a change of maintainer.

**A GPL-licensed icon set was added and withdrawn on August 19, 2026.** GPL copyleft covers the whole program, not only adaptations of the artwork, so bundling it would have ended the option of separate commercial terms. The standing rule is: prefer CC BY, never add GPL assets.

## 5. Name, trademark, and domains — the open risk

**The name Limeghost is not cleared.** This is the most significant unresolved IP item.

- No trademark search has been performed. `docs/product-foundation.md` records that a real search is required before public launch.
- The "Clear" prefix is crowded, which makes for a weak mark and raises the chance of an existing conflicting registration.
- `limeghost.com` was free on August 31, 2026, along with .net, .io, .ai and .co. Register them together; the previous name was lost to a holder who had taken the whole family. No company was found using the name, and WIPO's Global Brand Database should be run against it before any filing — see [brand/naming-decision-2026-08-31.md](brand/naming-decision-2026-08-31.md).

The current plan is to distribute from **`zincoo.com/limeghost`** — a domain the founder controls — following the pattern Firefox and Orion use, which also places an executable download on an established domain rather than a new one.

**Needs professional advice.** A trademark search and clearance opinion in the intended markets, before public launch and certainly before any transaction. A buyer will treat an uncleared name as a rebranding cost at best and an infringement risk at worst.

## 6. AI-assisted development — disclosed

Substantial parts of this codebase were written with AI coding assistants under the founder's direction. Commits record this in `Co-Authored-By` trailers. The history has not been rewritten to conceal it, and should not be.

**What is unsettled.** The copyrightability of AI-generated output is not resolved in law. The United States Copyright Office has taken the position that material generated without human authorship is not copyrightable, and the boundary for AI-*assisted* software has not been drawn by any court. This is a genuine open question for any software project built this way in 2026, not one specific to Limeghost.

**What supports human authorship here.** The record shows continuous human direction, selection, and judgment over the work as a whole:

- Product decisions with recorded reasoning, including rejected paths: the Library feature killed on evidence, the developer wedge reversed, a GPL icon set withdrawn for licensing reasons, the name reconsidered and kept.
- Editorial and honesty constraints the founder set and enforced: no fabricated tracker-block counts, risk signals never presented as verdicts, no claim of validation without observed users.
- Architecture and licensing decisions: the AGPL choice, the `LimeghostCore` boundary, the shared analysis contract, the favicon privacy policy.

These are recorded across `docs/`, `AGENTS.md`, and `CLAUDE.md`. That documentation is itself evidence of authorship and should be preserved, not trimmed.

**Needs professional advice.** How to characterise this in a transaction, and what representations can honestly be made about copyright in the codebase.

## 7. What transfers

If the project were sold or assigned, the following comprise the asset:

- Source code in this repository, all authored for this project.
- The Limeghost icon set (104 original marks) and the app icon.
- The Limeghost brand mark — the barn-owl face in a ring — in its three forms in `docs/brand/limeghost-mark-2026-08-31/`: full, small and one-colour. Commissioned by the founder and generated to his direction; no third-party artwork is incorporated, so it transfers as owned property rather than under a licence.
- Documentation in `docs/`, including the strategy, market, and research records.
- The product name, subject to section 5.
- The GitHub repository and its history.

Not included, or requiring separate arrangement: the Zincoo brand and `zincoo.com` if the founder retains them; any Apple Developer Program enrolment and signing identity, which is personal to its holder and cannot simply be handed over; the bundled third-party icon sets, which transfer subject to their own licences rather than as owned property.

## 8. Open items

| Item | Owner | Why it matters |
|---|---|---|
| Trademark search and clearance | Founder + counsel | Uncleared name is a rebranding cost or infringement risk |
| Legal entity and where copyright sits | Founder | Determines who can sign a transfer |
| Contributor agreement decision (CLA or DCO) | Founder | Sole ownership is the precondition for commercial relicensing |
| Position on AI-assisted authorship | Founder + counsel | Affects representations in any transaction |
| Apple Developer Program enrolment | Founder | Gates signing, notarization, and distribution — see `docs/macos-browser-foundation.md` |

## Related

[LICENSE](../LICENSE) · [privacy-and-safety.md](privacy-and-safety.md) · [data-inventory.md](data-inventory.md) · [product-foundation.md](product-foundation.md) · [macos-browser-foundation.md](macos-browser-foundation.md) · [limeghost-strategy.md](limeghost-strategy.md)
