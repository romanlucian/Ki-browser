# Local Analysis Evidence Integrity Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

> **Superseded, August 30, 2026.** This plan was completed, and the feature it hardened was then removed — key points, claims and Evidence Mode are gone. Kept as a record of work done and of the segmentation lessons it produced, which remain live in `CLAUDE.md` and the page-intelligence contract. Do not follow it.

**Goal:** Make every key point and claim that Analyze Page shows a verbatim substring of the page text, so Evidence Mode can actually highlight it.

**Architecture:** Replace the current "append a synthetic period, join, then split" pipeline with block-aware sentence splitting: the reading-block boundary *is* a sentence boundary, so no punctuation is ever invented. Add the missing terminator characters, guard decimals, and assess page structure by sentence density when block structure is unavailable. Contract first, then both runtimes.

**Tech Stack:** Swift 6 (`ClearframeCore`, XCTest), JavaScript (ES modules, `node --test`), shared JSON contract fixture.

**Spec:** [docs/local-analysis-evidence-defects.md](../../local-analysis-evidence-defects.md)

## Global Constraints

- **Contract first.** `macos/ClearframeBrowser/Tests/ClearframeCoreTests/Fixtures/local-analysis-contract.json` is the single source of truth. Change it first, then make both runtimes satisfy it. Never edit one implementation alone. (CLAUDE.md)
- **Two runtimes, one behaviour.** `macos/ClearframeBrowser/Sources/ClearframeCore/LocalAnalysisEngine.swift` and `src/core/analyzer.js` must stay behaviourally equivalent.
- **The invariant:** every entry in `keyPoints` and `claimsToCheck` MUST be a verbatim substring of `page.text`.
- **Adding a contract array requires three edits:** the JSON, the `LocalAnalysisContract` Decodable struct at `macos/ClearframeBrowser/Tests/ClearframeCoreTests/ClearframeCoreTests.swift:1162`, and a test in `test/analysis-contract.test.js`.
- **Do not reintroduce a merged multilingual stopword set.** Stopwords stay selected by declared language.
- **Risk heuristics stay context-aware.** Do not touch `RiskAnalyzer`.
- **Existing contract cases must keep passing.** The `zf.ro` extraction-pollution gate is permanent. If a change makes an existing case fail, stop and report — do not edit the expectation to match new behaviour without saying so explicitly.
- **No new dependencies.** No new Swift packages, no new npm packages.
- **Test commands:** `cd macos/ClearframeBrowser && swift test` and `npm test` from the repository root.
- **Do not touch** any documentation claim about signing, notarization, App Store readiness, or security review.

---

### Task 1: Add the evidence-integrity invariant to the contract and watch it fail

**Files:**
- Modify: `macos/ClearframeBrowser/Tests/ClearframeCoreTests/Fixtures/local-analysis-contract.json`
- Modify: `macos/ClearframeBrowser/Tests/ClearframeCoreTests/ClearframeCoreTests.swift` (struct at :1162, plus a new test method)
- Modify: `test/analysis-contract.test.js`

**Interfaces:**
- Consumes: nothing from earlier tasks.
- Produces: a contract array named `evidenceCases`, each element `{ "id": String, "page": <same shape as summaryCases[].page> }`. Task 2 and Task 4 must keep these passing.

- [ ] **Step 1: Add `evidenceCases` to the contract JSON**

Add this top-level key alongside the existing `summaryCases`. Reuse the exact `page` field names the existing `summaryCases` entries use (`title`, `url`, `hostname`, `scheme`, `language`, `text`, `wordCount`, `hasPasswordField`, `formActions`). Read one existing `summaryCases` entry first and copy its field spelling exactly.

```json
"evidenceCases": [
  {
    "id": "headline-listing-has-no-terminal-punctuation",
    "page": {
      "title": "Daily news",
      "url": "https://news.example/",
      "hostname": "news.example",
      "scheme": "https",
      "language": "en",
      "text": "Trump threatens Iran trade partners as strikes make way for economic pressure\nFamily of killed aid worker say she deserved more after investigation rejected\nVerstappen signs new Red Bull contract to stay in Formula One until 2030\nMagicians and margarine: ten of the funniest jokes from the Edinburgh fringe\nPremier League preview: Newcastle braced for a transitional season this year\nInstant classics, odd inspirations and barcodes: the best and worst kits seen\nSupreme Court rejects Verizon bid for a refund of its large regulatory fine\nVaccination rates fall again as exemptions continue to rise, new data shows\nFlight attendants raise the alarm that a large firm is buying location data\nAgainst all odds, a rocket company finally tugs its booster back into port\nPixel handset series review: is the magic finally starting to fade away now\nRegulator decides one gigabit per second is too fast for the new standard",
      "wordCount": 160,
      "hasPasswordField": false,
      "formActions": []
    }
  },
  {
    "id": "documentation-block-ending-in-colon",
    "page": {
      "title": "Tutorial",
      "url": "https://docs.example/tutorial",
      "hostname": "docs.example",
      "scheme": "https",
      "language": "en",
      "text": "Strings can be enclosed in single quotes or double quotes with the same result:\nIn the interactive interpreter, the output string is enclosed in quotes and special characters are escaped with backslashes.\nThe print function produces a more readable output, by omitting the enclosing quotes and by printing escaped and special characters.\nIf you do not want characters prefaced by a backslash to be interpreted as special characters, you can use raw strings by adding an r before the first quote.\nString literals can span multiple lines, and one way is using triple quotes so that line breaks are included automatically.",
      "wordCount": 96,
      "hasPasswordField": false,
      "formActions": []
    }
  },
  {
    "id": "decimal-numbers-are-not-sentence-boundaries",
    "page": {
      "title": "Laptop",
      "url": "https://shop.example/laptop",
      "hostname": "shop.example",
      "scheme": "https",
      "language": "en",
      "text": "The notebook is remarkably light at just 2.7 pounds and less than half an inch thin, according to the published specification sheet.\nBattery life is rated at 18.5 hours of video playback, which the manufacturer measured under a fixed brightness setting.\nThe display measures 13.6 inches diagonally and reaches 500 nits of sustained brightness in ordinary indoor conditions.\nStorage starts at 256 GB and the review unit shipped with 16 GB of unified memory installed at the factory.",
      "wordCount": 88,
      "hasPasswordField": false,
      "formActions": []
    }
  },
  {
    "id": "devanagari-danda-terminates-sentences",
    "page": {
      "title": "भारत",
      "url": "https://hi.example/bharat",
      "hostname": "hi.example",
      "scheme": "https",
      "language": "hi",
      "text": "भारत दक्षिण एशिया में स्थित एक विशाल देश है जिसकी जनसंख्या विश्व में सबसे अधिक है।\nयहाँ अनेक भाषाएँ बोली जाती हैं और प्रत्येक राज्य की अपनी सांस्कृतिक परंपरा है।\nदेश की अर्थव्यवस्था कृषि, उद्योग और सेवा क्षेत्र पर आधारित मानी जाती है।\nभारत की सीमाएँ अनेक देशों से मिलती हैं और इसके तीन ओर समुद्र स्थित है।",
      "wordCount": 62,
      "hasPasswordField": false,
      "formActions": []
    }
  }
]
```

- [ ] **Step 2: Extend the Swift `LocalAnalysisContract` struct**

At `macos/ClearframeBrowser/Tests/ClearframeCoreTests/ClearframeCoreTests.swift:1162`, add the field and the case type:

```swift
private struct LocalAnalysisContract: Decodable {
    let tokenCases: [TokenContractCase]
    let summaryCases: [SummaryContractCase]
    let structureCases: [StructureContractCase]
    let riskCases: [RiskContractCase]
    let plainEnglishCases: [PlainEnglishContractCase]
    let readingTimeCases: [ReadingTimeContractCase]
    let evidenceCases: [EvidenceContractCase]
}

private struct EvidenceContractCase: Decodable {
    let id: String
    let page: ContractPage
}
```

Reuse whatever the existing `SummaryContractCase` names its page type — read it and match. Do not introduce a second page struct.

- [ ] **Step 3: Add the Swift test**

Add to the same test class:

```swift
func testLocalAnalysisContractKeyPointsAndClaimsAreVerbatimPageText() throws {
    let contract = try localAnalysisContract()
    for testCase in contract.evidenceCases {
        let page = testCase.page.snapshot()
        let content = LocalAnalysisEngine.summarize(page: page)
        XCTAssertFalse(
            content.keyPoints.isEmpty && content.claimsToCheck.isEmpty,
            "\(testCase.id): produced no key points or claims to verify"
        )
        for point in content.keyPoints {
            XCTAssertTrue(
                page.text.contains(point),
                "\(testCase.id): key point is not verbatim page text — \(point)"
            )
        }
        for claim in content.claimsToCheck {
            XCTAssertTrue(
                page.text.contains(claim),
                "\(testCase.id): claim is not verbatim page text — \(claim)"
            )
        }
    }
}
```

`page.snapshot()` is whatever helper the existing summary test already uses to turn a contract page into a `PageSnapshot` — reuse it verbatim, do not write a new one.

- [ ] **Step 4: Add the JavaScript test**

Append to `test/analysis-contract.test.js`:

```js
test("shared contract: key points and claims are verbatim page text", () => {
  for (const testCase of contract.evidenceCases) {
    const page = extensionPage(testCase.page);
    const result = summarizeLocally(page);
    assert.ok(
      result.keyPoints.length > 0 || result.claimsToCheck.length > 0,
      `${testCase.id}: produced no key points or claims to verify`
    );
    for (const point of result.keyPoints) {
      assert.ok(
        testCase.page.text.includes(point),
        `${testCase.id}: key point is not verbatim page text — ${point}`
      );
    }
    for (const claim of result.claimsToCheck) {
      assert.ok(
        testCase.page.text.includes(claim),
        `${testCase.id}: claim is not verbatim page text — ${claim}`
      );
    }
  }
});
```

- [ ] **Step 5: Run both suites and verify they FAIL**

```bash
cd macos/ClearframeBrowser && swift test 2>&1 | tail -40
cd - && npm test 2>&1 | tail -40
```

Expected: the new tests FAIL in both runtimes. Expected failure text mentions `is not verbatim page text`. At least the `headline-listing` and `documentation-block-ending-in-colon` cases must fail.

**If a new test passes, stop and report** — the invariant is already held and the spec is wrong.

All pre-existing tests must still pass at this step. If any pre-existing test fails now, you broke the contract file — fix it before continuing.

- [ ] **Step 6: Commit**

```bash
git add macos/ClearframeBrowser/Tests/ClearframeCoreTests/Fixtures/local-analysis-contract.json \
        macos/ClearframeBrowser/Tests/ClearframeCoreTests/ClearframeCoreTests.swift \
        test/analysis-contract.test.js
git commit -m "test: assert key points and claims are verbatim page text

Adds evidenceCases to the shared contract and a failing assertion in both
runtimes. Documents the invariant Evidence Mode already depends on."
```

---

### Task 2: Block-aware sentence splitting in both runtimes

**Files:**
- Modify: `macos/ClearframeBrowser/Sources/ClearframeCore/LocalAnalysisEngine.swift`
- Modify: `src/core/analyzer.js`
- Test: existing suites — `swift test`, `npm test`

**Interfaces:**
- Consumes: `evidenceCases` from Task 1.
- Produces: `LocalAnalysisEngine.summarize(page:)` and `summarizeLocally(page)` keep identical signatures and identical output shape. `splitSentences` / the JS equivalent stay public with the same signature.

**Why this shape:** the current pipeline calls `normalizeReadingBlocks` (which appends `"."` to unterminated blocks and joins with `" "`) and then `splitSentences` over the joined string. That invented period reaches the user. Instead, split per block: a block boundary is a sentence boundary, so no punctuation needs inventing and every emitted sentence is a substring of its own block.

- [ ] **Step 1: Replace the Swift source pipeline**

In `summarize(page:)` (`LocalAnalysisEngine.swift:57`), replace:

```swift
let source = normalizeReadingBlocks(
    removeRepeatedMediaInterfaceText(page.text.isEmpty ? "" : page.text)
)
let sentences = deduplicated(splitSentences(source))
```

with:

```swift
let sentences = deduplicated(sentencesFromReadingBlocks(page.text))
```

Add:

```swift
/// A reading block boundary is a sentence boundary. Splitting per block removes
/// the need to invent terminal punctuation, so every emitted sentence stays a
/// verbatim substring of the page text that Evidence Mode will search for.
private static func sentencesFromReadingBlocks(_ value: String) -> [String] {
    guard !value.isEmpty else { return [] }
    return value
        .components(separatedBy: .newlines)
        .filter { !containsRepeatedMediaInterfaceText($0) }
        .flatMap { splitSentences($0) }
}
```

Replace `removeRepeatedMediaInterfaceText` with a predicate that drops an offending block instead of splicing its text (splicing rewrites the text and breaks verbatimness):

```swift
/// Embedded media players expose repeated accessibility controls through
/// `innerText`. Drop the whole block rather than splicing phrases out of it —
/// rewriting the text would make the sentence unfindable on the live page.
private static func containsRepeatedMediaInterfaceText(_ block: String) -> Bool {
    let matches = mediaInterfacePhrases.reduce(0) { count, phrase in
        count + matchCount(of: phrase, in: block)
    }
    return matches >= 2
}
```

Delete `normalizeReadingBlocks` and `removeRepeatedMediaInterfaceText` once nothing references them.

- [ ] **Step 2: Guard decimals and add the missing terminators in Swift**

In `splitSentences` (`LocalAnalysisEngine.swift:158`), change the ending set and add a decimal guard:

```swift
public static func splitSentences(_ value: String) -> [String] {
    var sentences: [String] = []
    var current = ""
    let endings: Set<Character> = [".", "!", "?", "。", "！", "？", "।", "॥", "۔", "؟"]
    let characters = Array(normalize(value))

    for (index, character) in characters.enumerated() {
        current.append(character)
        guard endings.contains(character) else { continue }
        // "2.7" is one number, not two sentences.
        if character == ".",
           index > 0, index + 1 < characters.count,
           characters[index - 1].isNumber, characters[index + 1].isNumber {
            continue
        }
        let sentence = normalize(current)
        if isUsefulSentenceLength(sentence) { sentences.append(sentence) }
        current = ""
    }

    let remainder = normalize(current)
    if isUsefulSentenceLength(remainder) { sentences.append(remainder) }
    return sentences
}
```

Also extend `blockEndings` (`LocalAnalysisEngine.swift:39`) so `assessStructure` recognises the same terminators:

```swift
private static let blockEndings: Set<Character> = [
    ".", "!", "?", "…", "。", "！", "？", ":", ";", "।", "॥", "۔", "؟"
]
```

- [ ] **Step 3: Mirror all of Step 1 and Step 2 in `src/core/analyzer.js`**

Read `src/core/analyzer.js` around `normalizeReadingBlocks` (line ~90) and `splitSentences`, and apply the identical changes: per-block splitting, block dropped when it holds two or more media-interface phrases, the same ten terminator characters, the same decimal guard, the same `blockEndings` extension. The two runtimes must produce identical output for every contract case.

- [ ] **Step 4: Run both suites and verify they PASS**

```bash
cd macos/ClearframeBrowser && swift test 2>&1 | tail -40
cd - && npm test 2>&1 | tail -40
```

Expected: Task 1's evidence tests now PASS in both runtimes, and **every pre-existing case still passes** — including the `zf.ro` media-pollution cases and all `summaryCases`.

If a pre-existing `summaryCases` expectation now fails, that is a real behaviour change. Report it with the before/after values. Do not silently update the expectation.

- [ ] **Step 5: Commit**

```bash
git add macos/ClearframeBrowser/Sources/ClearframeCore/LocalAnalysisEngine.swift src/core/analyzer.js
git commit -m "fix: split sentences per reading block instead of inventing periods

Block boundaries are sentence boundaries, so no synthetic terminator reaches
output and every key point stays a verbatim substring of the page text.
Adds Devanagari, Urdu and Arabic terminators and a decimal guard."
```

---

### Task 3: Assess structure by sentence density when block structure is absent

**Files:**
- Modify: `macos/ClearframeBrowser/Tests/ClearframeCoreTests/Fixtures/local-analysis-contract.json` (add to `structureCases`)
- Modify: `macos/ClearframeBrowser/Sources/ClearframeCore/LocalAnalysisEngine.swift` (`assessStructure`, :111)
- Modify: `src/core/analyzer.js` (`assessStructure`)

**Interfaces:**
- Consumes: the terminator sets from Task 2.
- Produces: no signature change. `assessStructure(page:) -> PageStructure` is unchanged.

**Why:** when the extractor finds fewer than two qualifying reading blocks it falls back to the whole body as one newline-free string. `assessStructure` then returns at the `blocks.count >= minimumListingBlocks` guard with `blocks.count == 1` and answers `.article` without ever counting punctuation — so Hacker News, the most listing-shaped page on the web, gets no section-page notice.

- [ ] **Step 1: Add the failing structure case**

Append to `structureCases` in the contract JSON. Match the field spelling of the existing entries exactly (`expected` is the string `"listing"` or `"article"`).

```json
{
  "id": "body-text-fallback-is-not-an-article",
  "page": {
    "title": "Hacker News",
    "url": "https://news.example/",
    "hostname": "news.example",
    "scheme": "https",
    "language": "en",
    "text": "A tale of two compilers (example.com) 119 points by luu 2 hours ago | hide | 48 comments 2. Why bloom filters still matter (example.com) 131 points by gavide 6 hours ago | hide | 21 comments 3. Show HN: I built a tiny database (example.com) 125 points by surprisetalk 9 hours ago | hide | 14 comments 4. The cost of abstraction (example.com) 191 points by mayoff 7 hours ago | hide | 83 comments 5. Rewriting our backend again (example.com) 57 points by worik 7 hours ago | hide | 32 comments 6. On the design of type systems (example.com) 159 points by jumploops 11 hours ago | hide | 103 comments 7. Ask HN: how do you stay focused 85 points by jggonz 11 hours ago | hide | 40 comments",
    "wordCount": 140,
    "hasPasswordField": false,
    "formActions": []
  },
  "expected": "listing"
}
```

- [ ] **Step 2: Run both suites and verify the new structure case FAILS**

```bash
cd macos/ClearframeBrowser && swift test 2>&1 | tail -30
cd - && npm test 2>&1 | tail -30
```

Expected: FAIL, reporting `article` where `listing` was expected. All other cases still pass.

- [ ] **Step 3: Fall back to sentence units in Swift**

In `assessStructure` (`LocalAnalysisEngine.swift:111`), replace the early guard so that a text with too few newline blocks is re-split into sentences and measured with the same two ratios, rather than assumed to be an article:

```swift
public static func assessStructure(page: PageSnapshot) -> PageStructure {
    var blocks = page.text.components(separatedBy: .newlines)
        .map(normalize)
        .filter { !$0.isEmpty }

    // The extractor falls back to one unsegmented run of body text when too few
    // reading blocks qualify. Measure sentences instead of asserting "article".
    if blocks.count < minimumListingBlocks && page.text.count >= fallbackTextCharacters {
        blocks = splitSentences(page.text)
    }
    guard blocks.count >= minimumListingBlocks else { return .article }

    // ... rest of the existing body unchanged ...
}
```

Add the constant next to the others (`LocalAnalysisEngine.swift:34-38`):

```swift
private static let fallbackTextCharacters = 1200
```

- [ ] **Step 4: Mirror in `src/core/analyzer.js`**

Apply the identical change and the identical `1200` constant to the JavaScript `assessStructure`.

- [ ] **Step 5: Run both suites and verify they PASS**

```bash
cd macos/ClearframeBrowser && swift test 2>&1 | tail -30
cd - && npm test 2>&1 | tail -30
```

Expected: all cases pass in both runtimes, including every pre-existing `structureCases` entry.

- [ ] **Step 6: Commit**

```bash
git add macos/ClearframeBrowser/Tests/ClearframeCoreTests/Fixtures/local-analysis-contract.json \
        macos/ClearframeBrowser/Sources/ClearframeCore/LocalAnalysisEngine.swift src/core/analyzer.js
git commit -m "fix: assess structure by sentence density on body-text fallback

A page whose extraction collapsed to one unsegmented run was assumed to be an
article without counting punctuation, so listing pages showed no section notice."
```

---

### Task 4: Make Evidence Mode matching resilient, and stop the panel claiming things that are false

**Files:**
- Modify: `macos/ClearframeBrowser/Sources/ClearframeBrowser/BrowserSession.swift` (`revealEvidence`, :423)
- Modify: `macos/ClearframeBrowser/Sources/ClearframeBrowser/AssistantPanel.swift` (:255-265)
- Test: `macos/ClearframeBrowser/Tests/BrowserBehaviorTests/`

**Interfaces:**
- Consumes: nothing from Tasks 1-3. This is the app layer; there is no contract case for it.
- Produces: no signature change. `revealEvidence(_:expectedNavigationVersion:) async -> Bool` is unchanged.

**Why:** even with Tasks 1-3 done, a class of failures remains — the needle is verbatim but spans two DOM elements, or lives outside `h1,h2,h3,p,li,blockquote`. Measured at 14/56 key points. And on any miss the panel currently blames the page for changing, which is not what happened.

- [ ] **Step 1: Widen the search and retry without trailing punctuation**

Read `BrowserSession.swift:423-510` first — the existing JavaScript already normalises whitespace on both sides of the comparison, so preserve that behaviour. Make two changes to the injected script:

1. Extend the candidate element list beyond `h1,h2,h3,p,li,blockquote` to include `td, dd, dt, figcaption, span` and, when no single element matches, fall back to searching the concatenated `innerText` of the nearest common container.
2. If the needle is not found, retry once with any trailing `.` `!` `?` `。` `！` `？` `।` `॥` `۔` `؟` stripped from the needle.

- [ ] **Step 2: Correct the two false strings**

In `AssistantPanel.swift`, the miss branch currently reads *"The live page changed or could not be highlighted."* Replace with wording that does not assert a cause:

```swift
Text(model.evidenceWasFoundOnPage
     ? "Highlighted in the page. This is extracted page text, not an AI citation."
     : "Shown here from the extracted page text. Clearframe could not locate it in the live page.")
```

- [ ] **Step 3: Add a behaviour test**

Add to `BrowserBehaviorTests` a test that a key point ending in a terminator still matches page text that lacks it, following the file's existing test style. Read a neighbouring test first and match its setup helpers.

- [ ] **Step 4: Run the suites**

```bash
cd macos/ClearframeBrowser && swift test 2>&1 | tail -30
```

Expected: all pass.

- [ ] **Step 5: Commit**

```bash
git add macos/ClearframeBrowser/Sources/ClearframeBrowser/BrowserSession.swift \
        macos/ClearframeBrowser/Sources/ClearframeBrowser/AssistantPanel.swift \
        macos/ClearframeBrowser/Tests/BrowserBehaviorTests
git commit -m "fix: widen evidence matching and stop blaming the page on a miss"
```

---

### Task 5: Update the documents the behaviour change invalidates

**Files:**
- Modify: `docs/clearframe-strategy.md`
- Modify: `docs/project-context.md`
- Modify: `CLAUDE.md`

**Interfaces:**
- Consumes: the completed behaviour from Tasks 1-4.
- Produces: nothing code-facing.

- [ ] **Step 1: Record the invariant and the language position**

In `docs/project-context.md` and `docs/clearframe-strategy.md`, add one line each stating that key points and claims are verbatim page text, enforced by `evidenceCases` in the shared contract.

In `CLAUDE.md`, extend the existing local-analysis bullet to name the invariant, and state which sentence terminators are recognised, so a future agent does not silently drop a script.

Do not claim any language is "supported" beyond what the contract actually covers. Deterministic coverage after this plan is English, Romanian, French, Simplified Chinese, and Hindi terminator handling — say exactly that.

- [ ] **Step 2: Commit**

```bash
git add docs/clearframe-strategy.md docs/project-context.md CLAUDE.md
git commit -m "docs: record the verbatim-evidence invariant and terminator coverage"
```

---

## Self-Review

**Spec coverage:** D1 → Task 2 Step 1. D2 → Task 2 Step 1 (block-aware splitting removes cross-block fusion; no intra-block `:` split, which would over-split ordinary prose). D3 → Task 2 Step 2. D4 → Task 3 (misclassification) and Task 4 Step 1 (unfindability). D5 → Task 2 Step 2. D6 → Task 4 Step 2. All six covered.

**Placeholder scan:** every code step carries real code. Task 2 Step 3 and Task 3 Step 4 direct the implementer to mirror named changes in a named file rather than repeating the JavaScript verbatim — deliberate, because the JS structure differs and a transcribed Swift idiom would not run.

**Type consistency:** `evidenceCases` is used with the same name in the JSON, the Swift struct, and the JS test. `sentencesFromReadingBlocks` and `containsRepeatedMediaInterfaceText` are introduced in Task 2 Step 1 and referenced nowhere else. `fallbackTextCharacters` is introduced and used only in Task 3.

**Known risk to watch:** Task 2 changes media-interface handling from splicing to block-dropping. If that alters an existing `zf.ro` `summaryCases` expectation, Task 2 Step 4 will catch it and the implementer must report rather than edit the expectation.
