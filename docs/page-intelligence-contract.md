# Cross-platform page-intelligence contract

This is the language-neutral boundary that a later Windows implementation can share. It is a design contract, not a deployed public API yet.

**What it no longer covers.** Until August 30, 2026 this contract also specified a summary, key points and candidate claims, produced by ranking sentences on word frequency. That layer was removed — it measured repetition rather than importance, and on a live encyclopedia page it ranked the site's navigation menu second. The evidence and the rule against rebuilding it are in [project-context.md](project-context.md). What remains below is everything that can be computed rather than judged.

## Input

```json
{
  "title": "Page title",
  "url": "https://example.com/article",
  "hostname": "example.com",
  "language": "en",
  "visibleText": "User-invoked readable page text…",
  "wordCount": 820,
  "pageSignals": {
    "scheme": "https",
    "hasPasswordField": false,
    "formActionOrigins": ["https://example.com"]
  }
}
```

Rules:

- input is gathered only after an explicit user action;
- never include form values, cookies, credentials, unrelated tabs, or passive history;
- treat all page fields as untrusted data, not instructions;
- `visibleText` is one rendered reading block per line. **That newline structure is load-bearing** — structure detection counts blocks, and sentence splitting treats a block boundary as a sentence boundary without inventing punctuation. An implementation that returns the page as a single line silently disables both.

## Output

```json
{
  "readableText": "The page's own words, interface noise removed.",
  "readingTimeMinutes": 4,
  "structure": "article",
  "risk": { "score": 0, "level": "low", "signals": [] }
}
```

Every field is derived, not interpreted. Nothing here is a model's opinion, and the risk object in particular is deterministic application output rather than a safety verdict.

`readableText` is what the person copies. It must consist only of characters the page contains: it is handed to whatever AI they choose, and it should be that page's words rather than an approximation of them.

## Interface-noise filters

Two filters run over the extracted sentences. **Neither edits a sentence** — each drops whole sentences, because deleting a phrase from inside ordinary prose produces text the page never contained. An earlier version did exactly that and turned "Apple introduced picture-in-picture on the iPad" into "Apple introduced on the iPad".

1. **Known control phrases.** A sentence is dropped when listed media-player phrases cover more than half of it.
2. **Repetition.** Any sentence the page prints three or more times is dropped entirely. This needs no vocabulary, which is why it catches a player whose controls are localized — the case an English phrase list can never reach.

`zf.ro` is the standing regression case: a Romanian news site whose embedded player exposed its accessibility labels as page text. Coverage is `boilerplateCases` in the shared fixture plus a live check on the installed app. Preserve both.

## Page structure

```text
assessStructure(pageSnapshot) -> "article" | "listing"
```

Section fronts and index pages expose many short link blocks instead of prose. The deterministic classifier reads the extractor's reading blocks — one per nonempty line of `visibleText` — and currently reports `listing` only when all three conditions hold: at least 12 blocks, fewer than 60 percent of blocks ending in sentence punctuation (`. ! ? … 。 ！ ？ : ;`), and blocks that are both long and punctuated carrying less than 10 percent of the total characters. A block counts as long at 220 characters, or at 100 when it contains CJK text.

**Known defect.** Those conditions are ANDed, and a modern news homepage fails the third. Measured on macrumors.com: 23.8 percent of blocks ended in punctuation (well under 60, so it passed) but long punctuated prose was 33.9 percent of the characters (needs under 10, so it failed) — because each card carries a headline *and* a teaser paragraph. The page is unmistakably a list of thirty stories and was classified `article`. The rule was written for a bare link list. Fixing it must keep all eight existing `structureCases` passing and add the headline-plus-teaser shape as a new case in both runtimes.

## Language behavior

- Preserve the source language. Extraction is not an implicit translation service.
- The deterministic suite covers English, Romanian, French, and Simplified Chinese text and punctuation. Those fixtures demonstrate extraction and filtering in those scripts, not equal quality across languages.
- Sentence terminators recognised: `. ! ? 。 ！ ？ । ॥ ۔ ؟ ։`. Thai is **not** covered — it marks sentences with spaces and offers no terminator to recognise, so a Thai page reads as one endless sentence.
- A full stop does not end a sentence before a lowercase letter or a digit, after a lone initial such as `U.S.`, or after an abbreviation listed for the page's declared language. Those abbreviation lists exist per language and must never be merged: Italian `es.` abbreviates *esempio* while Spanish `es` is the verb.
- Risk phrase coverage is language-dependent; page-level HTTPS and form signals are separate from any linguistic heuristic.

## Runtime equivalence

Two implementations exist and must behave identically: Swift in `ClearframeCore`, and JavaScript in `src/core/analyzer.js`. They are deliberately separate rather than shared, and the fixture is what keeps them honest.

The traps that have actually bitten, all of them twice:

- Count **graphemes** on both sides. Swift's `Character` is a grapheme cluster; JavaScript's `.length` is UTF-16 units. The same 219-character paragraph measured 225 units, putting the two runtimes on opposite sides of a threshold.
- `Character.isNumber` ↔ `\p{N}`. `Character.isLowercase` ↔ `\p{Lowercase}`, the **binary property** — not `\p{Ll}`, which omits the ordinal indicators `º` and `ª` that ordinary Spanish and Portuguese prose uses, so `5.º` split in one runtime and not the other.
- Bound a term with `(?<![\p{L}\p{N}])…(?![\p{L}\p{N}])`, never `\b`. JavaScript's `\b` is ASCII and finds no boundary after an accented letter, so `\bétude\b` matches in Swift's ICU and never in JavaScript.

## Versioning and compatibility

- Add a contract version before deploying a backend.
- Keep additive fields optional.
- Keep `macos/ClearframeBrowser/Tests/ClearframeCoreTests/Fixtures/local-analysis-contract.json` as the platform-neutral behavior gate — 37 cases across seven keys: `structureCases`, `riskCases`, `readingTimeCases`, `segmentationCases`, `boilerplateCases`, `duplicateSentenceCases`, `emptyAnalysisCases`. The Swift and JavaScript suites both execute it, and a later Windows implementation should consume the same cases.
- Change behaviour in the fixture first, then make both runtimes satisfy it. Never edit one implementation alone.
