# Clearframe: product and technical foundation

**Status:** standalone macOS version-1 MVP release stage plus an earlier extension validation artifact, August 2026
**Working name:** Clearframe; validate naming and trademarks before public launch.

## Product thesis

The browser market does not need another general-purpose Chromium wrapper with a chat box. Clearframe should win one repeated job first:

> Help me understand this unfamiliar page quickly, in language I can use, while making it easier to notice claims and obvious pressure tactics.

The first validation artifact was a side-panel extension. The chosen implementation direction is now a standalone macOS app built with SwiftUI and WebKit. It opens its own native window and owns navigation, while retaining the focused page-understanding assistant. This is still not a Chromium fork: maintaining Chromium would add security updates, packaging, sync, profiles, password migration, mobile support, and distribution work before product demand is known.

## First validation audience

Keep the product useful for ordinary people, researchers, students, and cross-border readers, but start founder-led validation with **photographers, designers, video creators, and creative freelancers who are overwhelmed by AI choices**. This is the current acquisition wedge from [go-to-market.md](go-to-market.md), not an exclusionary product boundary.

This audience is a better first recruiting segment than “everyone who browses” because it has:

- frequent, demonstrable decisions about unfamiliar AI tools and creative workflows;
- visual before/after use cases that can be explained without browser jargon;
- real client-reference, translation, vendor, tutorial, and source-comparison friction;
- measurable activation and return behavior before any monetization claim;
- founder-accessible communities for direct observation and zero-budget distribution.

Scam signals are a supporting trust feature, not the initial positioning. A small heuristic scanner must not be marketed as anti-phishing protection.

## Core user loop

1. The user opens a page in the standalone Clearframe browser.
2. Only after the user clicks Analyze Page, Clearframe extracts visible reading content and analyzes it locally.
3. The panel leads with the source, a short summary, key points, and claims to check.
4. The user can reveal exact local evidence, simplify an English-source summary locally, or explicitly send the disclosed minimized payload for an AI summary or translation.
5. The user can save a compact summary, navigate to a second source, and compare themes and figures.
6. The native browser can keep bookmarks, a capped local history, and recent-tab metadata in the Mac user profile. History and tab restoration can be disabled; browsing history is never uploaded to the AI provider or sold.
7. A new tab can help an ordinary user choose an AI service by task from a small static catalog, then open the service's official website without transferring the current page or an inferred prompt.

## MVP scope

### Included in the standalone macOS foundation

- Native SwiftUI application window with a real `WKWebView` page surface.
- Native first-run onboarding that explains the product promise, persists a visible search choice locally, states the local/cloud boundary, teaches Analyze page, and can be reopened from Settings.
- Independent regular/private tabs, recent regular-tab restoration, address/search, navigation controls, same-document URL/title tracking, loading, renderer-failure, and error states.
- Visible user choice among five web search providers, stored locally with no partnership claim.
- Task-first native AI-guide start page with locally defined task categories, local filtering, an explicit All Tools view, broad access hints, and ordinary links to listed services' official websites.
- User-confirmed downloads plus local bookmark/history organization, recovery backups, and an explicit local browsing-data reset.
- On-demand visible-page extraction from the app’s current web view.
- Local summary, candidate claims, read-time estimate, exact-text Evidence Mode, risk signals, English-source Plain English, and two-source comparison.
- Optional OpenAI provider behind a core protocol; user-owned prototype key stored in macOS Keychain.
- Clear separation between the Foundation-only analysis/service core and macOS-specific browser UI.

### Retained extension validation artifact

- On-demand extraction using temporary `activeTab` access.
- Offline extractive summary, key points, read-time estimate, and candidate claims.
- Obvious visible-page risk signals with explanations and a prominent non-verdict disclaimer.
- Plain English rewriting using a small local simplifier.
- Optional AI summary and translation through a modular provider.
- One-to-one source comparison using summary themes and extracted numbers.
- English-first interface and settings.

### Explicit non-goals

- A full Chromium fork, custom sync, password manager, or mobile browser.
- Autonomous clicking, purchasing, messaging, form submission, or account access.
- A “truth score,” political-bias score, malware verdict, or replacement for Safe Browsing.
- Remote browsing-history collection, cross-device history, ad insertion, or recommendation tracking.
- Claims of partnerships or bundled search contracts before signed agreements exist.
- Live AI-tool rankings, country-availability claims, precise price promises, affiliate redirects, or automatic transfer of page content and prompts to a listed service.

## Experience principles

1. **Source before answer.** Keep the page title and host next to every analysis.
2. **Local before cloud.** Useful summary and risk signals require no key or account.
3. **AI is a deliberate action.** Never upload page text merely because the panel opened.
4. **Explain uncertainty.** “Claim from the page” is different from “verified fact.”
5. **Read-only first.** Understanding creates value without giving an untrusted page control over an agent.
6. **One-screen value.** Summary, key points, and risks should be useful without a conversation.
7. **Editorial choices stay legible.** The start-page catalog is a small local guide, not a claim that one provider is universally best.
8. **Teach the differentiated action quickly.** First-run guidance should end at the AI home and show how to open a page and deliberately choose Analyze page.

## Technical shape

The native package has two targets:

- `ClearframeCore`: models, local analysis, risk heuristics, source comparison, and the remote-provider contract;
- `ClearframeBrowser`: SwiftUI, WebKit navigation/extraction, Keychain settings, and the assistant interface.

The extension artifact uses Manifest V3 with four narrow capabilities:

- `activeTab`: temporary current-page access after a toolbar click;
- `scripting`: execute the self-contained extractor in that tab;
- `sidePanel`: keep the analysis beside the page;
- `storage`: save settings and one compact comparison source.

Access to `api.openai.com` is an optional permission requested only when AI is enabled. There is no `<all_urls>` access, always-on content script, tabs-history permission, cookie access, web request interception, or background page-content collection.

The extension code is separated into:

- `src/content/extract-page.js` — visible page extraction;
- `src/core/analyzer.js` — local summary, simplification, and risk heuristics;
- `src/core/compare.js` — deterministic two-source comparison;
- `src/providers/openai.js` — optional AI adapter;
- `src/sidepanel.js` — product state and rendering.

The provider boundary should later support a production Clearframe service, enterprise model routing, and on-device models without rewriting either platform interface. A later Windows app should implement the same language-neutral page-intelligence request/response contract, while using a Windows-native UI and browser engine.

## AI and security boundary

Webpage text is untrusted. The optional AI prompt labels page content as data, tells the model not to obey embedded instructions, constrains analysis to a strict response schema, limits output, and keeps the feature read-only. Analysis sends the source title, hostname, declared language, and truncated extracted text while omitting the full URL, query, fragment, cookies, form values, and history. This reduces impact but does not solve prompt injection or remove sensitive text that may appear in the page body. Do not add tools, browser actions, credentials, private history, email, or file access to the same model context without a separate threat model, least-privilege design, and approval layer.

The prototype accepts a user-owned API key only to make local testing practical. Before any public paid plan:

- route calls through an authenticated backend;
- meter per-user usage and enforce hard budgets;
- remove secrets and sensitive fields before upload;
- add deletion, export, and retention controls;
- run prompt-injection and data-exfiltration tests;
- log only operational metadata required for reliability, never raw browsing history by default.

## Business model guardrails

The intended sequence is:

1. **Free basic product:** local summary, limited cloud assistance, comparison, and trust cues.
2. **AI Pro:** higher limits, stronger models, saved research sets, and export for heavy users.
3. **Business plans:** admin controls, policy, auditability, approved model routing, and team research—not employee surveillance.
4. **Search revenue share:** only after meaningful default-search volume exists and with user choice preserved.
5. **Intent-based partner recommendations:** clearly labeled, relevant, independently ranked, and never mixed invisibly into analysis.

Clearframe must not sell browsing histories, add hidden advertising, or bias risk/summary output because a merchant pays.

## Validation plan and gates

The next milestone is observed use, not feature count. The authoritative recruitment targets, consented metrics, weekly sequence, and stop/continue thresholds live only in [go-to-market.md](go-to-market.md); do not duplicate changing numbers here. The repository has no completed observed-session evidence yet. Record only aggregate, consented activation, hesitation, Analyze Page quality, return, and referral evidence—never passive browsing history.

Consider a production backend or Chromium architecture only after retained users demonstrate value and repeatedly encounter constraints that block it. The retained extension remains a lower-friction validation artifact, not a second primary product.

## Next engineering priorities

1. Test extraction against a corpus of news, documentation, shopping, forums, and international pages.
2. Extend the delivered local key-point highlighting into citation-grade evidence for gist, claims, translations, and provider-assisted output.
3. Add redaction for emails, phone numbers, account numbers, and form values before AI upload.
4. Replace raw-key mode with a metered backend and abuse controls.
5. Add a user-feedback affordance and privacy-preserving quality evaluation set.
6. Integrate established reputation services only after defining false-positive handling and appeal language.
