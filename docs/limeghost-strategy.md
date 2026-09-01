# Limeghost strategy and product memory

**Status:** August 2026. This is the durable product-direction brief for future developers and agents. Read it with [project-context.md](project-context.md) before changing scope.

## Plain-language overview

Limeghost is a real, standalone browser for ordinary people who want help navigating a complicated web. The current product is a native macOS application built with SwiftUI and WebKit. It should feel understandable, calm, and carefully made while helping users choose an AI tool, search the web, understand a page, compare sources, and notice explainable risk signals.

The primary promise is: **Limeghost makes the AI world simple for ordinary people.** Clarity matters more than feature count. Every major surface should help someone choose a useful next step without first learning model names, provider jargon, or browser internals.

The product is not a programmer-only browser, an AI chatbot wrapped around websites, a search engine, an antivirus product, or a generic Chrome clone. A separate programmer-focused concept exists for later exploration, but it must not redirect the current general-audience browser.

Limeghost's working differentiation is **“fast and calm even when the web is heavy.”** Treat that as a product objective to measure, not a superlative marketing claim. Never call it the world's lightest or fastest browser without reproducible independent evidence.

## Product decisions that must survive

- Build macOS first with native SwiftUI and WebKit. Do not switch the working app to Chromium now.
- Keep the isolated CEF work as a future gate for demonstrated cross-platform or Chromium-extension needs. It is not linked into today's app and is not permission to begin a disruptive engine migration.
- Keep the interface English-first while supporting pages across languages, and test with ordinary people. Technical depth should not leak into the first-minute experience.
- Preserve radical clarity, high craft, calm interaction, and trust before monetization.
- Keep visual browsing and search. Voice is an explicit additional input, never background listening.
- Keep AI read-only unless a separate action threat model, confirmation design, and security review exist.
- Never promise revenue, popularity, safety, truth, or feature completeness.

## The magic first minute

The first minute is a product acceptance criterion, not a marketing slogan:

1. A new tab begins with a clear human goal or task rather than an undifferentiated model list.
2. Limeghost presents a small, useful set of AI paths with plain-language reasons for choosing each one.
3. After the user opens a webpage, Analyze Page makes it easier to understand and shows why its output is grounded in that page.

The current build partially delivers this: onboarding hands off to a genuinely task-first AI home that keeps the full catalog behind an explicit All Tools action, and Analyze Page pulls the readable article out of a page, explains any visible risk signals, and hands the text to whichever AI the person already uses. It shows the complete payload and its size before copying anything. It does not summarize the page or decide what matters in it — that layer was removed on August 30, 2026, and the reasoning is recorded in [project-context.md](project-context.md).

## Current product state

The installed local version currently includes:

- an independent macOS window with SwiftUI browser chrome and WebKit rendering;
- multiple tabs with safe close/teardown, recent regular-tab restoration, ephemeral private tabs, and local session metadata;
- address/search input plus a local choice of DuckDuckGo, Google, Bing, Brave Search, or Startpage;
- loading, offline, timeout, blocked-link, and general error states;
- a visible native bookmarks bar with local top-level links, nested emoji-folder menus, safe current-page/saved-bookmark drag filing, the full local folder organizer, capped history, and user-confirmed downloads with a clear toolbar status/destination panel;
- a native first-run introduction and a Settings action to revisit it;
- a task-first curated AI home organized around Ask & Learn, Write, Research, Create Images, Create Videos, Translate, and Code;
- user-triggered Analyze Page with source-language extraction, reading time, explained risk signals, a listing-page notice, and Copy for AI, with Reader (`⇧⌘R`) as the full-payload preview;
- explicit on-device voice dictation into the visible address field for review;
- an optional provider contract and user-owned prototype key stored in macOS Keychain;
- local-data recovery from last-known-good records, a user-confirmed browsing-data reset, WebKit process-failure handling, and visible page dialog/media-permission prompts;
- a section-page structure notice: Analyze Page recognizes listing/index pages, explains that they list many articles rather than one text, and offers an explicit Analyze anyway instead of silently stitching headlines;
- default-on tracker blocking against a small, versioned, first-party curated domain list through WebKit's content-rule engine, with an address-bar shield, per-site exceptions, and state-only status text (WebKit cannot count blocked requests; Limeghost never shows block numbers) — see [the content-blocking policy](content-blocking.md);
- a redesigned single-row dark interface: hidden system title bar with inline traffic lights, identity-dot tab chips, a unified address pill, a slim bookmarks bar, and all colors centralized in one theme;
- a full-page bookmarks home with visual folder cards, rolled-up link/subfolder counts, search across bookmarks and folder names, drill-down, and local history — while new tabs and Home keep opening the AI guide.

The AI home is a small catalog bundled with the app. It links directly to official provider destinations. Within a selected task, a few sourced editorial badges can make the first choice simpler; they must remain sparse, dated, explained, and governed by [the AI catalog editorial policy](ai-catalog-editorial.md). They are not universal or live rankings, Limeghost product tests, partnerships, an endorsement marketplace, affiliate feed, exact-price tracker, regional-availability promise, or automatic prompt router. Selecting a card does not attach the current page or a user prompt.

The installed app is a hardened-runtime, ad hoc local build with an icon and privacy manifest. It is not Developer ID signed, notarized, distributed through TestFlight or the App Store, independently security reviewed, or ready to make production password-manager claims.

## Multilingual Analyze Page requirement

Analyze Page must work on pages across languages, not only English or Romanian. Limeghost privately extracts rendered reading content and keeps it in the page's declared or dominant language. Deterministic coverage currently includes English, Romanian, French, and Simplified Chinese, including media-control pollution checks.

That coverage proves the pipeline can preserve those scripts; it does not prove equal quality for every language. Text-based risk phrases, sentence segmentation, and reading-time estimates all have language-specific limits. Understanding a page in any language is now the job of whichever AI the person pastes it into, not of Limeghost.

## Recent quality gate

The high-priority August 2026 extraction issue on complex news pages such as `zf.ro` allowed embedded video-player accessibility/control strings into the analysed text — and would now put them on somebody's clipboard. The current build prioritizes rendered reading blocks, excludes hidden/media/control/navigation/consent UI, removes repeated boilerplate, and preserves legitimate article language. The fix passed deterministic Romanian fixtures and a live installed-app check on `https://www.zf.ro/`; keep that coverage as a permanent regression gate.

More broadly, “fast and calm” requires measured QA across real sites and realistic tab counts. Video playback can be resource intensive in every major browser. Diagnose Limeghost-specific waste with evidence; do not promise impossible zero-cost video playback or make speculative engine changes.

## Next differentiated experiences

After extraction quality, the next differentiated product work is:

1. **A reader that can be checked.** Whatever eventually understands a page — Apple's on-device model, an API the person configures, or something else — should return quotes it says are from the page, which Limeghost then verifies by substring test before showing. Grounding checked rather than asserted. That is the one thing the big AI browsers cannot claim, and it survives the removal of everything built on top of it.
2. **Extraction quality.** Everything above reads what extraction produces, so its ceiling is the product's ceiling. Currently the extractor takes the first `<article>` or `<main>` with 400+ characters and otherwise the whole page body, and discards every block under 45 characters — which silently deletes prices, ingredients, specifications and forum replies.

Neither is delivered. Both require usability testing before release, and neither should start before an outside tester can install the app at all.

## Privacy and security boundaries

- Analyze Page runs only after an explicit click and is local by default.
- Extracted text is the page's own words and never carries a character the page lacks — it goes on somebody's clipboard and into somebody's AI. The shared contract's `segmentationCases` keep both runtimes splitting sentences identically, which matters because the interface-noise filters count whole sentences. Deterministic coverage is English, Romanian, French, and Simplified Chinese, plus Devanagari, Urdu, Arabic and Armenian sentence terminators; Thai is not covered, having no terminator character. Abbreviation lists that keep `Dr. Alison` or `Dl. Popescu` in one piece exist for English, Romanian, French, Spanish, German and Italian; they prevent a wrong split and are not a claim of analysis quality in those languages.
- Opening a page never silently uploads it to an AI provider.
- Optional online AI is separately enabled, visibly triggered, and uses a user-owned prototype key. Analysis sends only the source title, hostname, declared language, and truncated extracted text—not the full URL, query, fragment, cookies, form values, or history. Do not ship a shared client key.
- Never sell browsing history. History, bookmarks, and recent-tab metadata remain local with user controls.
- Do not append hidden affiliate or tracking parameters to AI-home links.
- Do not add telemetry by default, hidden advertising, covert recommendation bias, or fabricated partnerships.
- Treat page text as untrusted input. Do not let it trigger actions, purchases, messages, permission changes, or data access.
- Risk signals are explainable heuristics, not malware, scam, truth, or safety verdicts.
- Tracker blocking is local and honest: a bundled, versioned, first-party curated list compiled on-device, with per-site exceptions stored locally. It is not a complete ad blocker, shows state rather than counts, and is never presented as a safety verdict.
- Voice capture must be user-triggered, visibly active, reviewable, and stoppable. No wake word or silent cloud fallback.

See [privacy-and-safety.md](privacy-and-safety.md) for the operational data boundary and release-security gaps.

## Monetization order

Monetization follows demonstrated user value and trust:

1. Keep a genuinely useful free browser.
2. Offer optional Pro for heavy AI or research usage after costs and value are measured.
3. Add team plans only when administration, approved model routing, and organizational controls are credible.
4. Explore default-search economics or transparent intent-based referrals only at meaningful scale and with clear labeling.

Never sell browsing history. Never let payment, referral, or search relationships silently change extraction, risk signals, or AI-home ordering. There is no guarantee that any of these models will produce revenue.

## Lean, zero-budget launch approach

The detailed creator wedge, hypotheses, measurement boundaries, weekly cadence, and 30/60/90-day stop rules live in [the focused go-to-market plan](go-to-market.md).

Early distribution should optimize for learning, not inflated reach:

- Give founder-led demonstrations that show one concrete confusing task before and after Limeghost.
- Invite a personal network, creative community, and other ordinary-user early testers; observe where they hesitate instead of coaching past every problem.
- Publish short, honest before/after demonstrations of choosing an AI path or understanding a difficult page.
- Build in public through the GitHub repository with clear release notes, known limits, and visible quality work.
- Learn from observed usage and direct conversations, then improve the first minute before expanding the feature list.

Do not buy paid ads before retention is understood. Do not spam communities, fabricate testimonials or usage, imply partnerships, manufacture urgency, or promise guaranteed growth.

## Explicit non-goals

- A Chromium or CEF engine switch in the current product cycle.
- A full Chromium source fork.
- Building an independent search index in the browser MVP.
- Replacing VS Code or turning Limeghost into a programmer-only product.
- Live or universal “best AI” rankings, unsourced badges, claimed partnerships, auto-sharing prompts/pages, or precise provider-price promises.
- Autonomous transactions, silent page actions, or a generalized agent with broad browser permissions.
- Password-manager, download-safety, security-verdict, signing, notarization, or App Store claims before the corresponding work and review exist.
- Paywalling the first-minute experience.

## Ordered roadmap

### 1. Quality and validation

- Keep the closed `zf.ro` extraction-pollution gate covered by deterministic and live regression checks.
- Build a representative extraction corpus across news, documentation, shopping, forums, international pages, paywalls, and hostile markup.
- Expand multilingual fixtures and real-page QA beyond the current English, Romanian, French, and Simplified Chinese coverage without promising uniform quality.
- Measure tab, memory, loading, and video behavior before making performance claims.
- Test the onboarding, AI home, search choice, and Analyze Page with ordinary users; fix confusion before expanding scope.

### 2. Trustworthy differentiation

- Replace the extractor's tag-and-blocklist approach with scored content extraction that can abstain when it cannot find the article.
- When a reader arrives, make it quote rather than assert, and verify every quote against the page before showing it.
- Improve accessibility, keyboard behavior, page-permission clarity, and granular per-site browsing-data controls beyond the delivered all-data reset.

### 3. Release engineering

- Complete threat modeling, security and privacy review, crash recovery, updater design, and broader hardware/site QA.
- Obtain Apple Developer credentials, then perform Developer ID signing, notarization, and an appropriate TestFlight/App Store or direct-distribution evaluation.
- Add production observability only with a transparent, minimal, consent-aware design.

### 4. Sustainable paid use

- Introduce optional metered Pro only after a secure authenticated backend, cost controls, abuse prevention, and clear free limits exist.
- Validate team requirements before building team administration.
- Consider search or referral revenue only later, with transparent labels and strict separation from intelligence output.

### 5. Platform expansion gate

- Revisit the isolated CEF path only when cross-platform demand or extension compatibility is proven and WebKit parity, update cadence, licensing, helper-process packaging, privacy, and distribution risks are understood.
- Keep the current WebKit app releasable until a replacement passes explicit parity gates.

## Practical continuity

- GitHub repository: [romanlucian/Ki-browser](https://github.com/romanlucian/Ki-browser)
- Primary agent instructions: [../AGENTS.md](../AGENTS.md)
- Durable implementation decisions: [project-context.md](project-context.md)
- Build and release gaps: [macos-browser-foundation.md](macos-browser-foundation.md)
- Run and test commands: [the root README](../README.md#verify-the-native-code)

Future agents must inspect the current tree and test state before editing, preserve unrelated work, update documentation when boundaries change, and never revive a rejected path merely because it appeared in an older prototype or conversation.
