# On-device AI design (Apple Foundation Models)

**Status:** Design only, rewritten August 30, 2026. Nothing here is implemented.

**This document was rewritten because its premise died.** The first version designed a model into the local summarize path — the model would pick sentences by index out of a ranked candidate list, so key points stayed verbatim and Evidence Mode kept working. That whole layer was removed on August 30, 2026: the ranking measured word repetition rather than importance, and Evidence Mode had no entry point once key points were gone. See [project-context.md](project-context.md).

What survives is the research, which is worth keeping, and a simpler design that does not depend on anything deleted.

## Verified facts

Measured on the founder's Mac, not inferred:

- **macOS 26.5, Apple M2 Pro, 16 GB.** `/System/Library/Frameworks/FoundationModels.framework` is present.
- **Apple Intelligence is currently OFF.** `SystemLanguageModel.default.availability` returns `.unavailable(.appleIntelligenceNotEnabled)`. Nothing on this path can be tested until it is switched on in System Settings.
- **The API matches what the framework's own interface declares:** `SystemLanguageModel.default`, `.availability`, `.isAvailable`, `.supportsLocale(_:)`, `.supportedLanguages`, `UseCase.general`/`.contentTagging`, `Guardrails`, `LanguageModelSession(model:tools:instructions:)`, `respond(to:generating:)` returning `Response<Content>`, `streamResponse`, `@Generable`, `@Guide`, `GenerationOptions`, `tokenCount(for:)` on 26.4+, and a `Tool` protocol. `Availability.UnavailableReason` is `deviceNotEligible` / `appleIntelligenceNotEnabled` / `modelNotReady`.
- **23 supported languages**, read at runtime rather than hardcoded:

  ```
  da  de  en(AU/GB/US)  es(419/ES/US)  fr(CA/FR)  it  ja  ko
  nb  nl  pt(BR/PT)  sv  tr  vi  zh-Hans  zh-Hant(HK/TW)
  ```

  **Romanian is not among them** — the founder's own daily reading. English, French and both Chinese scripts are, so three of Limeghost's four tested languages are covered and twenty-two more are gained that the deterministic pipeline never served.

- **The context window is about 4,096 tokens**, covering instructions, schema, input *and* output together. Roughly 12,000 characters of article once the rest is allowed for. Extraction caps at 48,000. Both pages the founder tested during the removal work — a Britannica section at 32,801 characters and the MacRumors homepage at 25,527 — are several times over budget. This is the constraint that shapes everything else, and it was missed entirely by the first design.

## Constraints that bite

- **CI runs `macos-15`.** `FoundationModels` needs macOS 26, so every reference needs `#if canImport(FoundationModels)` and `@available(macOS 26, *)`. A green local build proves nothing. CI does not pin an Xcode version, which should be fixed at the same time.
- `Package.swift` selects `swiftLanguageModes: [.v5]`, so Swift 6 strict concurrency is *not* enforced — but a model call is still async work that a navigation can supersede, and `PageAssistantModel` already has generation and navigation-version checks that any new path must respect.
- Apple exposes distinct refusal and guardrail errors. Do not collapse them into one silent failure; a page that trips a guardrail is different from a model that is unavailable.

## The design

Not index selection. **The model reads, and Limeghost checks what it says.**

```text
readableText(page)          →  clean article, interface noise already removed
        │
   Apple model, guided generation, chunked to fit the context window
        │
   { summary: String, quotes: [String] }
        │
   every quote checked: is this string actually in the page text?
        │
   passes → shown as a quote     fails → dropped
```

Why this rather than indices:

- **It needs nothing that was deleted.** No candidate list, no scoring, no ranked array whose index numbering was ambiguous — a real defect the first design carried.
- **The guarantee is verified rather than constructed.** A substring test is one line and cannot be wrong. The first design achieved the same guarantee by never letting the model emit text, which also meant it could only ever choose from a pre-filtered shortlist.
- **The model sees prose, not a numbered list**, which is what it is good at.

The honest limit is that a model can paraphrase when asked to quote, and a paraphrase fails the check and disappears. That is the correct failure: better a missing quote than an invented one.

## What it must not do

- **Never touch risk signals.** They are deterministic, explainable rules with published thresholds. A model's opinion about danger is not a risk signal and must never be presented as one.
- **Never claim the summary is grounded.** The summary is written. Only the quotes are checked. If the interface implies otherwise it is lying, and quietly.
- **Never run without being asked.** Analyze page is the explicit action; the model runs inside it, not before it.

## Sequencing

This is not the next thing to do, for a reason that has not changed: `spctl --assess` reports the built app as **rejected**. It is ad-hoc signed and not notarized, so no outside tester can open Limeghost at all, and no amount of analysis quality matters to somebody who cannot launch it.

1. Developer ID signing and notarization
2. Observed sessions with real testers
3. Extraction quality — everything here reads what extraction produces, so its ceiling is this feature's ceiling
4. This document
5. A downloadable model — only if a non-Apple platform becomes real, or if observed users hit the Romanian gap and mind

## One thing to know before starting

**The founder is the worst available tester of this feature.** Apple Intelligence is off on his Mac, and his daily reading is Romanian — the one language Apple omits. Dogfooding normally would exercise the fallback every day and never the feature. Turn Apple Intelligence on and read English, French or Chinese pages through it deliberately, or the first person to genuinely run this code will be a stranger.
