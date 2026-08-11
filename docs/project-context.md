# Durable project context

**Status:** August 2026. This file records decisions that should survive beyond any one conversation or development tool.

The companion [Clearframe strategy and product memory](clearframe-strategy.md) is the authoritative plain-language vision, non-goals, sequencing, and continuity brief. The trusted GitHub repository is [romanlucian/Ki-browser](https://github.com/romanlucian/Ki-browser).

## Product decision

Clearframe is a real, standalone, macOS-first browser for ordinary English-speaking users. The delivered and installed version owns its native window and currently renders pages with SwiftUI + WebKit. The earlier Chromium side-panel extension remains useful validation work, but it is not the current product and must not be presented as the finished browser.

The selected migration path for a future Chromium-based Clearframe is the official Chromium Embedded Framework (CEF), hosted behind a narrow Objective-C++ bridge while retaining SwiftUI and `ClearframeCore`. The isolated scaffold at `chromium/cef-spike` is architecture validation only: it is not linked into the current app, does not make the installed app Chromium, and is not a full Chromium source fork. Keep WebKit as the working baseline until the CEF build meets documented parity, privacy, security-update, and distribution gates.

The focused promise is to help people understand unfamiliar pages quickly: summarize readable content, surface claims worth checking, simplify or translate content, compare two sources, and explain obvious visible risk signals. It is not a generic Chrome clone, a truth engine, or an antivirus product.

The primary user promise is **“Clearframe makes the AI world simple for ordinary people.”** Clarity outranks feature count. The magic first minute should begin from a recognizable goal, show a small useful set of AI paths, and make an open page understandable with honest grounding. The current AI home and extractive Analyze Page are the foundation; exact supporting-sentence Evidence Mode remains future work.

The quality objective is “fast and calm even when the web is heavy.” This is a measurable design goal, not permission to claim Clearframe is the world's lightest or fastest browser without evidence. Radical clarity, high craft, ordinary users, trust before monetization, and real-person testing are standing principles.

Voice is an additional primary interface, not a replacement for visual search or cited visual answers. The first voice phase is explicit, on-device dictation into the visible search/address field. There is no wake word, background listening, automatic submission, or autonomous transaction.

## AI and privacy decisions

- Useful summaries, Plain English, comparison, and risk signals work locally without an account or API key.
- Visible page text is extracted only when the user requests analysis.
- Optional provider use is separately triggered and disclosed. Prototype credentials are user-owned and stored in macOS Keychain.
- Browsing history is never sold. Current bookmarks, capped history, and recent-tab metadata stay in the local Mac user profile and have user controls.
- Page content is untrusted. The assistant remains read-only and receives no cookies, form values, passwords, unrelated tabs, or browsing-history feed.
- The new-tab AI guide is a static catalog bundled with the app. Filtering is local, cards use direct official HTTPS destinations, and Clearframe does not attach page content, prompts, affiliate tags, or tracking parameters.
- The guide is not a live ranking, provider partnership, availability guarantee, or auto-sharing router.

## Business direction

The intended sequence is a free useful browser, optional AI Pro for heavy usage, business plans with administration and approved model routing, and search revenue sharing only after meaningful scale exists. Transparent intent-based partner recommendations may be explored later, but they must be clearly labeled and must never alter summaries or risk signals invisibly.

Product sequencing is validation and quality first, then Evidence Mode and Translate & Explain, then release/security work, optional Pro, team plans, and only later search/referral economics. This is a direction, not a revenue guarantee.

The initial launch approach is intentionally lean and zero-budget: founder-led demonstrations, personal-network and creative-community early testers, short honest before/after examples, a public GitHub build narrative, and learning from observed use. Do not use fake claims, spam, implied partnerships, premature paid advertising, or guaranteed-growth language.

Building an independent search index is a separate, capital-intensive future business. It is not part of the current browser MVP. DuckDuckGo is the initial search default, but users can visibly choose DuckDuckGo, Google, Bing, Brave Search, or Startpage from the address bar or Settings. The choice is stored locally, and no provider partnership or revenue agreement is claimed.

## Scope boundaries

A programmer-focused browsing workspace is documented as a separate future concept. It may connect documentation, GitHub, code explanation, research, and VS Code workflows, but it must not redirect the current general-audience browser or create a second browser product now.

A later Windows client may reproduce the language-neutral page-intelligence contract, but the current native SwiftUI UI is intentionally macOS-specific. The macOS Chromium migration work does not select a Windows UI or packaging stack.

Do not switch rendering engines now. CEF remains a future gated path for demonstrated cross-platform or Chromium-extension needs, after parity, security-update, privacy, licensing, packaging, and distribution requirements are met.

## Delivered version-1 capabilities

- Standalone native window with startup activation and address-field focus.
- Explicit on-device voice-input shell with visible status and review-before-submit behavior.
- Independent tabs, safe close/teardown, new-tab links, and tab keyboard commands.
- Local restoration of up to 12 recent tab URLs/titles with lazy loading and an opt-out.
- Back, forward, home, reload, stop, address/search, progress, HTTPS indication, and clear loading/offline/error states.
- A visible search-provider chooser with a locally persisted selection; direct website addresses bypass search.
- A polished native new-tab AI guide organized around Ask & Learn, Write, Research, Create Images, Create Videos, Translate, and Code, with a local filter and direct official-site cards. Gemini's image guidance and the separate Veo and Seedance video cards use cautious, provider-controlled availability language. Activating a card navigates the current tab, exposes the exact destination immediately, and shows provider-specific loading feedback.
- A three-step, locally completed first-run introduction covering the product promise, five-provider search choice, local/cloud privacy boundary, AI home, and the user-triggered Analyze page workflow. It can be reopened from Settings without clearing tabs or data and contains no paywall or purchase flow.
- User-confirmed downloads with destination, status, cancel, reveal, and clear controls.
- Local bookmarks and searchable capped history with remove, clear, and disable controls.
- User-triggered local summary, key points, claims, reading time, Plain English, visible risk signals, and two-source comparison.
- Optional OpenAI provider through a reusable protocol and macOS Keychain-backed prototype settings.
- A locally built app bundle at `dist/Clearframe.app`; it uses only an ad hoc local signature and is not Developer ID signed or notarized.

## Extraction quality regression gate

Complex news pages can expose embedded media-player controls and accessibility boilerplate as text. `zf.ro` is the standing regression case. The current fix filters rendered reading blocks and Romanian analysis so subtitles, stream, playback, hidden, consent, and navigation UI do not enter the gist, key points, or claims. It passed deterministic fixtures and an installed-app live check on `https://www.zf.ro/`; preserve both forms of coverage.

## Remaining release gaps

This is a practical MVP, not a Chrome/Safari-scale production browser. Remaining work includes broader navigation and hostile-page QA, private browsing, multiple profiles, tab reordering/groups, sync, comprehensive site permissions and certificate UI, a security-reviewed password/import system, complete browsing-data deletion, persisted/resumable downloads and scanning, crash reporting, updater infrastructure, accessibility QA, a production AI backend, independent security review, Developer ID signing, notarization, and public distribution work.
