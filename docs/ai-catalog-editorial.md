# AI catalog editorial and update policy

**Current catalog:** `2026.08.11.1`, manually checked August 11, 2026.

Clearframe’s AI home is a small local guide for ordinary users. Catalog records live in `macos/ClearframeBrowser/Sources/ClearframeCore/AIToolCatalogData.swift`, compile into the app, and change only through a reviewed app update. There is no catalog server, analytics feed, affiliate ordering, or automatic remote fetch in this phase.

## What the labels mean

- **Best Overall** means the editor considers the tool the strongest general starting point for one named task within Clearframe’s small catalog.
- **Best Value** means a useful task-focused web entry can be tried before a user decides whether paid access is worthwhile. It is not a price comparison.
- **Easiest to Start** means the product presents a comparatively direct or template-led path for that named task. It is not a measured speed or usability benchmark.
- **Free to Try**, **Paid Plan**, and **Provider Terms** are broad orientation labels. They are not exact prices or promises that a feature, account, trial, or plan is available in every country.

Badges appear only after a task is selected. They are editorial shortcuts based on official product descriptions, not universal rankings, independent performance tests, provider payments, or real-time availability checks. Tools without enough neutral support receive no badge.

## Current badge rationale and official sources

| Task | Badge | Tool | Editorial rationale | Official source |
|---|---|---|---|---|
| Ask & Learn | Best Overall | ChatGPT | Broad documented coverage of everyday questions, learning, writing, images, and code. | [OpenAI ChatGPT FAQ](https://help.openai.com/en/articles/12677804-what-is-chatgpt-faq) |
| Write | Best Overall | Claude | A focused path for drafting, revising, and working through long written material. | [Anthropic Claude](https://www.anthropic.com/claude) |
| Research | Best Overall | Perplexity | A research-first interface that presents web sources with answers. | [Perplexity product explanation](https://www.perplexity.ai/help-center/en/articles/10352901-what-is-perplexity) |
| Code | Best Value | DeepSeek | A code-focused web entry point that can be tried before choosing paid access. | [DeepSeek](https://www.deepseek.com/) |
| Create Videos | Easiest to Start | Canva | A template-led, visual route to assembling and editing video. | [Canva video editor](https://www.canva.com/video-editor/) |
| Translate | Best Overall | DeepL | A dedicated text and document translation surface rather than a general chat tool. | [DeepL document translation](https://www.deepl.com/en/features/document-translation) |

These rationales describe intended product focus. Clearframe has not benchmarked the providers against one another, and provider-controlled features and terms can change after the checked date.

## Manual weekly review workflow

The target cadence is one short editorial review each week while the catalog is actively maintained. A missed review does not silently refresh the displayed date.

1. Open every destination and badge-source URL on its provider’s official HTTPS domain. Remove or correct broken, redirected-to-unrelated, or unsafe links.
2. Read the provider’s current product and plan pages. Check only broad task fit and whether the access label remains honest; do not copy exact prices into the app.
3. Review every badge against the definitions above. Remove a badge when evidence is ambiguous rather than filling every category.
4. Check category size, plain-language card copy, provider balance, and regional/plan caveats. Do not infer worldwide availability.
5. Check whether any listed provider is under a regulatory block, ban, or major intellectual-property action in a market Clearframe ships to. Listing one is an editorial decision, not an automatic removal — but make it deliberately and record the reasoning, so the history shows a decision rather than an oversight.
6. Update the checked date and catalog version only after the full review. Add or update an official-source URL for every badge rationale.
7. Run `swift test`, the native smoke test where the macOS host permits it, and review the AI home visually at narrow and wide window sizes.
8. Commit the configuration, tests, and this rationale together so the Git history explains the change.

No provider can buy a badge or position. A future commercial relationship must be clearly labeled in a separate surface and must not silently alter this editorial ordering.

## Naming these products, and what to do if a provider objects

The catalog names other companies' products and links to their official sites. That is referential use: a directory cannot describe a tool without naming it, so the names appear as plain text in the app's own typeface, with no logo, no brand styling, and no artwork of any provider bundled with Clearframe. A tool's own icon appears only if the reader has opened it and the browser captured it during that visit, the same way it captures any site's icon. The AI home states in the app that Clearframe is independent, is not affiliated with or endorsed by any listed provider, and that the names are their owners' trademarks.

**If a provider objects**, in writing and from an address that plausibly represents them: correct the entry, or remove the card, in the next update. Do not argue the point in public and do not wait for a review cycle. Record the objection and what was done about it below.

**Objections received:** none as of August 25, 2026.

## Future secure remote-update design

A remote catalog may be useful after Clearframe has release infrastructure, but it must fail closed and carry data only—never executable Swift, JavaScript, HTML, prompts, or WebKit configuration. A production design should use:

- a first-party Clearframe HTTPS endpoint, not arbitrary raw GitHub URLs;
- a small versioned schema with strict field lengths, known badge/access enums, HTTPS-only destinations, and an explicit provider-domain allowlist;
- a signed manifest verified with a public key embedded in the app, plus issue/expiry dates and monotonic versions to prevent replay or downgrade;
- staged publishing, human approval, an auditable change log, rollback, and a last-known-good bundled fallback;
- normal app sandbox/network controls, bounded caching, and no user identifier, browsing history, tool-search text, or click data in update requests;
- tests that reject unknown fields where safety-relevant, invalid signatures, expired data, oversized content, tracking parameters, and non-HTTPS links.

Until that infrastructure, threat model, and release review exist, the bundled Swift configuration remains the safer source of truth.
