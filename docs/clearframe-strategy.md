# Clearframe strategy and product memory

**Status:** August 2026. This is the durable product-direction brief for future developers and agents. Read it with [project-context.md](project-context.md) before changing scope.

## Plain-language overview

Clearframe is a real, standalone browser for ordinary people who want help navigating a complicated web. The current product is a native macOS application built with SwiftUI and WebKit. It should feel understandable, calm, and carefully made while helping users choose an AI tool, search the web, understand a page, compare sources, and notice explainable risk signals.

The primary promise is: **Clearframe makes the AI world simple for ordinary people.** Clarity matters more than feature count. Every major surface should help someone choose a useful next step without first learning model names, provider jargon, or browser internals.

The product is not a programmer-only browser, an AI chatbot wrapped around websites, a search engine, an antivirus product, or a generic Chrome clone. A separate programmer-focused concept exists for later exploration, but it must not redirect the current general-audience browser.

Clearframe's working differentiation is **“fast and calm even when the web is heavy.”** Treat that as a product objective to measure, not a superlative marketing claim. Never call it the world's lightest or fastest browser without reproducible independent evidence.

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
2. Clearframe presents a small, useful set of AI paths with plain-language reasons for choosing each one.
3. After the user opens a webpage, Analyze Page makes it easier to understand and shows why its output is grounded in that page.

The current build partially delivers this: onboarding hands off to a task-category AI home, the catalog is deliberately small and locally defined, and Analyze Page produces an extractive local gist, key points, claims, and risk explanations. Local key points now have Evidence Mode: users can reveal the exact extracted sentence and Clearframe attempts to highlight it in the live page. This is grounding, not a guarantee of page truth or a perfect citation system; provider-written summaries are not presented as automatic evidence.

## Current product state

The installed local version currently includes:

- an independent macOS window with SwiftUI browser chrome and WebKit rendering;
- multiple tabs with safe close/teardown, recent-tab restoration, and local session metadata;
- address/search input plus a local choice of DuckDuckGo, Google, Bing, Brave Search, or Startpage;
- loading, offline, timeout, blocked-link, and general error states;
- a visible native bookmarks bar with local top-level links, nested emoji-folder menus, safe current-page/saved-bookmark drag filing, the full local folder organizer, capped history, and user-confirmed downloads with a clear toolbar status/destination panel;
- a native first-run introduction and a Settings action to revisit it;
- a curated AI home organized around Ask & Learn, Write, Research, Create Images, Create Videos, Translate, and Code;
- user-triggered Analyze Page with a local extractive gist, key points, candidate claims, reading time, explained risk signals, English-source Plain English simplification, and two-source comparison;
- explicit on-device voice dictation into the visible address field for review;
- an optional provider contract and user-owned prototype key stored in macOS Keychain.

The AI home is a small catalog bundled with the app. It links directly to official provider destinations. Within a selected task, a few sourced editorial badges can make the first choice simpler; they must remain sparse, dated, explained, and governed by [the AI catalog editorial policy](ai-catalog-editorial.md). They are not universal or live rankings, Clearframe product tests, partnerships, an endorsement marketplace, affiliate feed, exact-price tracker, regional-availability promise, or automatic prompt router. Selecting a card does not attach the current page or a user prompt.

The installed app is an ad hoc local build. It is not Developer ID signed, notarized, distributed through TestFlight or the App Store, independently security reviewed, or ready to make production password-manager claims.

## Multilingual Analyze Page requirement

Analyze Page must work on pages across languages, not only English or Romanian. Local mode privately extracts rendered reading content, keeps it in the page's declared or dominant language, and structures representative sentences into a gist and key points. Deterministic coverage currently includes English, Romanian, French, and Simplified Chinese, including media-control pollution checks.

That coverage proves the pipeline can preserve and structure those scripts; it does not prove equal linguistic or semantic quality for every language. Local mode is extractive rather than a deep semantic model. Candidate-claim terms, text-based risk phrases, Plain English rewriting, tokenization, and reading-time estimates have language-specific limits. A configured optional provider may provide richer multilingual summarization or translation, but only after an explicit user action that sends the disclosed page text. Provider quality and language coverage depend on the selected model.

## Recent quality gate

The high-priority August 2026 extraction issue on complex news pages such as `zf.ro` allowed embedded video-player accessibility/control strings into the local gist, key points, and claims. The current build prioritizes rendered reading blocks, excludes hidden/media/control/navigation/consent UI, removes repeated boilerplate, and preserves legitimate article language. The fix passed deterministic Romanian fixtures and a live installed-app check on `https://www.zf.ro/`; keep that coverage as a permanent regression gate.

More broadly, “fast and calm” requires measured QA across real sites and realistic tab counts. Video playback can be resource intensive in every major browser. Diagnose Clearframe-specific waste with evidence; do not promise impossible zero-cost video playback or make speculative engine changes.

## Next differentiated experiences

After extraction quality and release fundamentals, the next product ideas are:

1. **Evidence Mode:** show the exact page sentences supporting each gist point or claim so users can inspect context instead of trusting a floating summary.
2. **Translate & Explain:** preserve source links while translating or explaining unfamiliar language, terms, and context in plain language.

These are directions, not delivered features. They require usability testing, source-grounding tests, and clear local/cloud disclosure before release.

## Privacy and security boundaries

- Analyze Page runs only after an explicit click and is local by default.
- Opening a page never silently uploads it to an AI provider.
- Optional online AI is separately enabled, visibly triggered, and uses a user-owned prototype key. Do not ship a shared client key.
- Never sell browsing history. History, bookmarks, and recent-tab metadata remain local with user controls.
- Do not append hidden affiliate or tracking parameters to AI-home links.
- Do not add telemetry by default, hidden advertising, covert recommendation bias, or fabricated partnerships.
- Treat page text as untrusted input. Do not let it trigger actions, purchases, messages, permission changes, or data access.
- Risk signals are explainable heuristics, not malware, scam, truth, or safety verdicts.
- Voice capture must be user-triggered, visibly active, reviewable, and stoppable. No wake word or silent cloud fallback.

See [privacy-and-safety.md](privacy-and-safety.md) for the operational data boundary and release-security gaps.

## Monetization order

Monetization follows demonstrated user value and trust:

1. Keep a genuinely useful free browser.
2. Offer optional Pro for heavy AI or research usage after costs and value are measured.
3. Add team plans only when administration, approved model routing, and organizational controls are credible.
4. Explore default-search economics or transparent intent-based referrals only at meaningful scale and with clear labeling.

Never sell browsing history. Never let payment, referral, or search relationships silently change summaries, evidence, risk signals, or AI-home ordering. There is no guarantee that any of these models will produce revenue.

## Lean, zero-budget launch approach

The detailed creator wedge, hypotheses, measurement boundaries, weekly cadence, and 30/60/90-day stop rules live in [the focused go-to-market plan](go-to-market.md).

Early distribution should optimize for learning, not inflated reach:

- Give founder-led demonstrations that show one concrete confusing task before and after Clearframe.
- Invite a personal network, creative community, and other ordinary-user early testers; observe where they hesitate instead of coaching past every problem.
- Publish short, honest before/after demonstrations of choosing an AI path or understanding a difficult page.
- Build in public through the GitHub repository with clear release notes, known limits, and visible quality work.
- Learn from observed usage and direct conversations, then improve the first minute before expanding the feature list.

Do not buy paid ads before retention is understood. Do not spam communities, fabricate testimonials or usage, imply partnerships, manufacture urgency, or promise guaranteed growth.

## Explicit non-goals

- A Chromium or CEF engine switch in the current product cycle.
- A full Chromium source fork.
- Building an independent search index in the browser MVP.
- Replacing VS Code or turning Clearframe into a programmer-only product.
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

- Prototype Evidence Mode with inspectable source sentences.
- Prototype Translate & Explain with explicit provider/local boundaries and source preservation.
- Improve accessibility, keyboard behavior, page-permission clarity, and complete browsing-data controls.

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
