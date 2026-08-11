# Clearframe repository guidance

Use [AGENTS.md](AGENTS.md) as the authoritative development instruction file. Read both [docs/clearframe-strategy.md](docs/clearframe-strategy.md) and [docs/project-context.md](docs/project-context.md) before proposing or implementing product-direction changes.

Essential constraints:

- The current installed product is a standalone, macOS-first SwiftUI + WebKit browser for ordinary users.
- Do not switch the current product to Chromium. The isolated CEF scaffold is only a future cross-platform/extension gate; it is not linked into the app and is not a full Chromium source fork.
- The root browser extension is a retained validation artifact, not the primary deliverable.
- Page assistance is local-first; optional provider use happens only after an explicit user action.
- Analyze Page must preserve source-language text across languages. Local mode is private extractive structuring, currently tested in English, Romanian, French, and Simplified Chinese; optional configured AI may provide deeper multilingual synthesis. Never claim uniform semantic quality or multilingual risk-detection parity.
- The AI home is a curated local directory of official links. Its sparse task badges, broad access labels, checked date, and source links follow [docs/ai-catalog-editorial.md](docs/ai-catalog-editorial.md); they are not universal/live rankings, Clearframe testing, partnerships, exact prices, affiliate ordering, or automatic page/prompt sharing.
- Never sell browsing history, add hidden ads, invent partnerships, or market heuristic risk signals as security verdicts.
- Prioritize extraction quality, measured calm performance, real-user clarity, Evidence Mode/Translate & Explain, and release security before broad feature expansion or monetization.
- The primary promise is “Clearframe makes the AI world simple for ordinary people.” Optimize the first minute around a human task, a small set of useful AI paths, and understandable page analysis. Do not present future exact Evidence Mode as delivered.
- Favor founder-led demos, real early testers, honest before/after examples, GitHub build notes, and observed learning. Do not recommend spam, fake traction, premature paid ads, or guaranteed-growth claims.
- Preserve the `ClearframeCore` versus macOS UI/WebKit boundary and document material behavior or data-flow changes.
- Do not claim production signing, notarization, App Store readiness, password security, or security review without evidence.

Do not revive rejected paths from old prototypes or conversations without explicit user direction and evidence. The root [README](README.md#documentation-index) links the strategy, product, architecture, privacy, research, run, and release-gap documents. The trusted upstream is `https://github.com/romanlucian/Ki-browser`; never rewrite it casually.
