# Local analysis: evidence-integrity defects

**Status:** August 20, 2026. Findings only — no fix applied at the time of writing. This is the spec that `docs/superpowers/plans/2026-08-20-local-analysis-evidence-integrity.md` implements.

**Where each defect stands, August 25, 2026.** The findings below are left as they were written; this is what has since changed.

| | State | By what |
|---|---|---|
| D1 synthetic terminator | Closed for extraction | No terminator is invented for a key point or claim. One remains inside `simplifyEnglish`, which rewrites English by design and is not the verbatim path Evidence Mode reads. |
| D2 colon and semicolon fusion | Not re-measured | Still open as written until someone re-runs it. |
| D3 decimal splits | Closed | The digit guard is in both runtimes and has a contract case. |
| D4 body-text fallback | Closed | `tr` joined the reading selector (`3df4151`, nested rows `55137c7`), so an aggregator no longer reaches the fallback: live `news.ycombinator.com` goes from nothing recognised to sixty per-entry blocks. `tr` also joined the Evidence Mode candidates (`5a75e28`), because a row-derived key point spans several cells and no `td` holds it. The fallback itself remains unusable for its stated purpose and this is worth recording: it reads `innerText` from a **detached clone**, which WebKit gives textContent semantics, so it never sees a layout line break at all. |
| D5 Indic and other terminators | Closed except Thai | The danda is in the terminator sets, and Armenian `։` was added in `648ce48`. Thai stays out because it separates sentences with spaces and has no terminator character to recognise — measured, not assumed. |
| D6 false user-facing strings | Substantially closed | The engine no longer alters a sentence on the extraction path, so "This is extracted page text" is true again: the media-control filter stopped editing prose (`e4417e5`) and Swift stopped collapsing zero-width spaces the page still contains (`3df4151`). A miss now means what the string says. |

Two further defects of this class were found and fixed while closing the above, neither of them in the list: the media-control filter deleted its phrases from inside ordinary sentences, and Swift's whitespace set disagreed with the JavaScript extractor's on U+200B, U+0085 and U+FEFF. Both emitted text the page did not contain.

## The invariant that is currently unstated and currently violated

Evidence Mode works by string identity. `PageAssistantModel.revealEvidence(for:session:)` hands a key point verbatim to `BrowserSession.revealEvidence(_:expectedNavigationVersion:)`, which searches the live page for that exact text and highlights it. The assistant panel states the guarantee to the user: *"This is extracted page text, not an AI citation."*

That guarantee depends on an invariant nothing in the repository asserts:

> Every entry in `keyPoints` and `claimsToCheck` must be a verbatim substring of `page.text`.

`local-analysis-contract.json` contains zero cases covering it. Both runtimes violate it identically, so the parity tests pass while the guarantee fails.

## How this was measured

Two independent runs against live pages in a real `WKWebView`, using the byte-identical extraction script lifted from `BrowserSession.swift` and the repository's own `LocalAnalysisEngine`:

- Run A: 9 pages, 4 languages.
- Run B (adversarial, separate agent, different site list): 14 pages, 7 languages, plus a live-DOM probe reproducing the real `revealEvidence` matching logic.

Combined result across Run B's 56 key points: **46/56 verbatim (82%), 38/56 actually highlightable (68%).**

| Page class | Verbatim | Highlightable |
|---|---|---|
| Wiki articles (7 languages) | 83% | 83% |
| Product pages | 100% | 100% |
| **Listings / home pages** | 81% | **31%** |
| Documentation | 25% | 25% |

Language is not the axis. Japanese, Korean, Arabic (RTL), German, Spanish and French articles perform at English-article parity. The worst results are English or structural: `news.ycombinator.com` 0/4 highlightable, `docs.python.org` 1/4 verbatim.

The one genuine language failure is Indic script — see D5.

## The defects

### D1 — Synthetic terminator is emitted into output

`LocalAnalysisEngine.swift:227` and `src/core/analyzer.js:92`:

```swift
return block + "."          // Swift
```
```js
/[.!?。！？:;]$/u.test(block) ? block : `${block}.`   // JS
```

`normalizeReadingBlocks` appends a period to any reading block lacking terminal punctuation, so that separate headlines are not fused into one sentence. The intent is correct; the side effect is that the emitted sentence carries a character the page never contained.

Accounts for **63%** of non-verbatim cases in Run B. Deterministic reproduction (12 unpunctuated headlines): **0/6 verbatim, 6/6 recovered by stripping the trailing period.**

### D2 — Colon and semicolon blocks fuse into the next block

`normalizeReadingBlocks` treats `:` and `;` as existing terminators (`LocalAnalysisEngine.swift:225`) and leaves those blocks untouched. `splitSentences` (`LocalAnalysisEngine.swift:161`) does **not** include `:` or `;` in its ending set, so the run continues into the following block.

Accounts for the remaining **37%** of non-verbatim cases, and is the dominant failure on documentation pages: `docs.python.org` produced 1/4 key points and 0/3 claims.

### D3 — `splitSentences` splits inside decimal numbers

`2.7` becomes `"…just 2."` and `"7 pounds…"`. Language-independent. It preferentially corrupts `claimsToCheck`, which are selected *because* they contain digits.

### D4 — Verbatim but unfindable: the body-text fallback

When fewer than two reading blocks qualify (`blocks.length >= 2` in the extraction script), the script falls back to the whole `innerText` as a single newline-free string. Consequences:

1. Output becomes fragments of interleaved metadata — `news.ycombinator.com` gist begins `com/oldnewthing)119 points by luu 2 hours ago | hide | 48 comments2.`
2. `assessStructure` returns at the `blocks.count >= minimumListingBlocks` guard (`LocalAnalysisEngine.swift:115`) with `blocks.count == 1`, so it answers `.article` **without ever counting punctuation** — and the section-page notice never appears on the pages that need it most.
3. Every key point is verbatim yet **0/4 highlightable**, because `revealEvidence` only searches `h1,h2,h3,p,li,blockquote` and requires the needle inside a single element.

Confirmed on `news.ycombinator.com` and `cnnespanol.cnn.com` (7/7 verbatim, 0/7 findable each).

Note: an earlier hypothesis blamed HN rank numbers (`"2."`) for inflating the punctuated-block count. That mechanism was refuted for HN — the guard fires first — but it does occur in the wild: `heise.de` has 117 blocks, 81% period-terminated teasers, and is misclassified `.article`.

### D5 — Indic and other sentence terminators are unrecognised

The danda `।` appears in none of the three ending sets (`LocalAnalysisEngine.swift:39`, `:161`, `:225`). Effect on `hi.wikipedia.org/wiki/भारत`, a long prose article:

- `assessStructure` → **listing** (22% "punctuated", 2% prose mass) — a flagship article gets the section-page notice.
- Key points 2/4 verbatim; claims **0/3**.

Same class applies to Urdu `۔`, Armenian `։`, and Thai (no terminator character).

### D6 — Two user-facing strings are false when evidence fails

`AssistantPanel.swift:260-263`:

- On a miss: *"The live page changed or could not be highlighted."* The page did not change; the engine altered the sentence.
- The fallback box states *"This is extracted page text"* while displaying characters that were never on the page.

This is a direct conflict with the trust positioning in `clearframe-strategy.md`.

## Scope decision

Keep multilingual local analysis. Restricting to English would remove functionality that measurably works across seven languages while leaving every defect above in place. D5 is the one real language gap and is fixed by adding terminator characters, not by narrowing scope.

An on-device or cloud model does not address any defect here — all six occur before any model would run, and a fluent model layered on D4's fragment soup would conceal the failure rather than repair it. See `docs/on-device-ai-design.md`, which depends on correctly-bounded verbatim sentences being available to select from.
