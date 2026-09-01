# Limeghost: product and technical foundation

**Status:** standalone macOS version-1 MVP release stage plus an earlier extension validation artifact, August 2026
**Name:** Limeghost, kept after a deliberate review on August 19, 2026. It carries a true double meaning for a browser, it reads calm rather than boastful, which is the product's whole posture, and it generated the app mark: an empty frame with the icon set's turned corner. Alternatives were considered and rejected — a studio name on a consumer browser reads as a side project, and grander names contradict a product whose differentiation is refusing to overclaim.

Two costs are accepted knowingly and are not settled by this decision:

- The "Clear" prefix is crowded in software, which makes for a weak trademark. A proper trademark search is still required before any public launch, and it may yet force a change.
- `limeghost.com` and every other extension checked (.net, .io, .ai, .co) were free on August 31, 2026 and should be registered together. The plan is still to ship from `zincoo.com/limeghost`, the pattern Firefox and Orion use, which puts the download on an established studio domain rather than a new one — a trust advantage when the file being downloaded is a browser.

The strongest naming evidence is still missing: no one outside the founder has used the product. Watch what observed testers call it before treating the name as final.

## Product thesis

The browser market does not need another general-purpose Chromium wrapper with a chat box. Limeghost should win one repeated job first:

> Get this unfamiliar page into a shape I can actually work with — the article without the clutter, ready for the AI I already use — and warn me about obvious pressure tactics on the way.

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

1. The user opens a page in the standalone Limeghost browser.
2. Only after the user clicks Analyze Page, Limeghost extracts visible reading content and analyzes it locally.
3. The panel leads with the source, the read time, and any visible risk signals.
4. The user opens Reader to see the complete payload and its size, or presses ⇧⌘C to skip that, and pastes it into whichever AI they use.
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
- Source-language extraction with interface noise removed, read-time estimate, risk signals, a listing-page notice, Copy for AI, and Reader as the full-payload preview.
- An assistant beside the page: the person's own ChatGPT, Claude, Gemini, Le Chat or Grok in a web view, one per window, signed in with their own account. It survives switching tabs, hiding, and switching assistant. Compare answers puts two of them side by side in the window.
- No AI of Limeghost's own: no provider, no key, no request.
- Clear separation between the Foundation-only analysis/service core and macOS-specific browser UI.

### Retained extension validation artifact

- On-demand extraction using temporary `activeTab` access.
- Offline extraction and read-time estimate.
- Obvious visible-page risk signals with explanations and a prominent non-verdict disclaimer.
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
2. **Local, full stop.** Extraction and risk signals require no key, no account, and no network request. Limeghost reaches no AI service at all.
3. **AI is a deliberate action.** Never upload page text merely because the panel opened.
4. **Explain uncertainty.** “Claim from the page” is different from “verified fact.”
5. **Read-only first.** Understanding creates value without giving an untrusted page control over an agent.
6. **One-screen value.** What the page is, what is worth noticing about it, and its text ready to hand over — all without a conversation.
7. **Editorial choices stay legible.** The start-page catalog is a small local guide, not a claim that one provider is universally best.
8. **Teach the differentiated action quickly.** First-run guidance should end at the AI home and show how to open a page and deliberately choose Analyze page.

## Technical shape

The native package has two targets:

- `LimeghostCore`: models, text preparation, structure detection, and risk heuristics;
- `LimeghostBrowser`: SwiftUI, WebKit navigation/extraction, Keychain settings, and the assistant interface.

The extension artifact uses Manifest V3 with four narrow capabilities:

- `activeTab`: temporary current-page access after a toolbar click;
- `scripting`: execute the self-contained extractor in that tab;
- `sidePanel`: keep the analysis beside the page;
- `storage`: save settings and one compact comparison source.

Access to `api.openai.com` is an optional permission requested only when AI is enabled. There is no `<all_urls>` access, always-on content script, tabs-history permission, cookie access, web request interception, or background page-content collection.

The extension code is separated into:

- `src/content/extract-page.js` — visible page extraction;
- `src/core/analyzer.js` — text preparation, structure detection, and risk heuristics;
- `src/providers/openai.js` — optional AI adapter;
- `src/sidepanel.js` — product state and rendering.

The provider boundary should later support a production Limeghost service, enterprise model routing, and on-device models without rewriting either platform interface. A later Windows app should implement the same language-neutral page-intelligence request/response contract, while using a Windows-native UI and browser engine.

## AI and security boundary

Webpage text is untrusted, and every local rule that reads it treats it as data rather than instructions.

**Limeghost holds no credential and calls no model.** The assistant beside the page is a web view showing that provider's ordinary website, signed in with the person's own account, under that provider's own terms. Limeghost sends it nothing. Text reaches it the way text reaches any site — the person copies and pastes it, and presses send themselves.

That boundary is not a preference and must not be optimized away. Filling a provider's input box from Limeghost, or pressing its send button, would be automated access to a service Limeghost has no agreement with; Anthropic's consumer terms prohibit it explicitly, and the others read the same way. Compare answers is deliberately two manual pastes for this reason: one box driving two providers would cross exactly this line. A link clicked inside the assistant opens in a tab rather than navigating the panel, because navigating the panel away is how a conversation gets lost.

If Limeghost ever does hold a credential and call a model, then before any public paid plan:

- route calls through an authenticated backend;
- meter per-user usage and enforce hard budgets;
- remove secrets and sensitive fields before upload;
- add deletion, export, and retention controls;
- run prompt-injection and data-exfiltration tests;
- log only operational metadata required for reliability, never raw browsing history by default.

## Business model guardrails

The intended sequence is:

1. **Free basic product:** extraction, risk signals, and trust cues. Note that the paid tiers below assumed Limeghost would provide the AI, which it no longer does — see the business note in [project-context.md](project-context.md).
2. **AI Pro:** higher limits, stronger models, saved research sets, and export for heavy users.
3. **Business plans:** admin controls, policy, auditability, approved model routing, and team research—not employee surveillance.
4. **Search revenue share:** only after meaningful default-search volume exists and with user choice preserved.
5. **Intent-based partner recommendations:** clearly labeled, relevant, independently ranked, and never mixed invisibly into analysis.

Limeghost must not sell browsing histories, add hidden advertising, or bias extraction or risk output because a merchant pays.

## Validation plan and gates

The next milestone is observed use, not feature count. The authoritative recruitment targets, consented metrics, weekly sequence, and stop/continue thresholds live only in [go-to-market.md](go-to-market.md); do not duplicate changing numbers here. The repository has no completed observed-session evidence yet. Record only aggregate, consented activation, hesitation, Analyze Page quality, return, and referral evidence—never passive browsing history.

Consider a production backend or Chromium architecture only after retained users demonstrate value and repeatedly encounter constraints that block it. The retained extension remains a lower-friction validation artifact, not a second primary product.

## Next engineering priorities

1. Test extraction against a corpus of news, documentation, shopping, forums, and international pages.
2. Replace the extractor's tag-and-blocklist approach with scored content extraction that abstains when it cannot find the article.
3. Add redaction for emails, phone numbers, account numbers, and form values before AI upload.
4. Replace raw-key mode with a metered backend and abuse controls.
5. Add a user-feedback affordance and privacy-preserving quality evaluation set.
6. Integrate established reputation services only after defining false-positive handling and appeal language.
