# Privacy and safety notes

Clearframe is designed as an on-demand reading tool, not a browsing monitor. The primary implementation is now a standalone macOS SwiftUI/WebKit app; the earlier extension follows the same local-first boundary.

## Prototype data flow

### Native local mode (default)

- The WebKit browser renders the page inside Clearframe’s own window.
- Visible page text is extracted only when the user clicks **Analyze page**.
- The local extractor removes hidden controls, navigation/consent chrome, and recognizable embedded-media UI before analysis; it does not inspect media streams.
- Local multilingual mode keeps extracted sentences in the page language. Optional provider-assisted multilingual synthesis or translation sends the disclosed text only after the user separately requests that action.
- No form values, cookies, passwords, bookmarks, or history feed are included in the extraction result.
- Local analysis runs in the app process.
- A saved source comparison is kept only in memory in this foundation.
- Bookmarks, their titled/emoji folder hierarchy, bookmarks-bar visibility, completed-visit history, and recent regular-tab URL/title metadata stay in the local Mac user profile. Valid records maintain last-known-good local backups; unreadable primary bytes are quarantined instead of silently replacing them. The bar, native context menus, and deliberate URL drag/drop actions read/write the same local records and make no network request of their own. Drag filing accepts only credential-free `http`/`https` URLs; the same normalized URL is moved rather than duplicated. Legacy bookmarks without folder data remain visible as Unfiled. Users can hide the bar without deleting data, remove bookmarks, clear or disable future history, and disable tab restoration; this phase has no bookmark account or sync service.
- Private tabs use a non-persistent WebKit website-data store and are excluded from history and restored-session metadata. They do not provide network anonymity, hide traffic from websites or network operators, or prevent an explicitly saved bookmark/download from persisting.
- Tracker blocking runs entirely inside WebKit's local content-rule-list engine against a bundled, first-party curated domain list (see [docs/content-blocking.md](content-blocking.md)). The on/off state and per-site exceptions stay in local `UserDefaults`, apply in private tabs too, and are cleared by the Settings reset below. WebKit applies the compiled rules inside the page process, so Clearframe never receives a report of which requests were blocked.
- Clearframe identifies itself to websites as Safari, because it renders with WebKit — the engine Safari ships. A `WKWebView` otherwise sends no `Version`/`Safari` token, and sites that vary pages by user agent answer that with a reduced page kept for unrecognised clients. The Safari version is read from the copy installed on the Mac. Clearframe sends no identifier of its own, no additional header, and nothing about the user; this string is the same for every Clearframe install on a given macOS version.
- Site icons are captured only while the user is visiting a site, from that site's own declared icon or its `/favicon.ico`, and never through a third-party icon service. Icons are downscaled and cached in the local Mac user profile (`Application Support/Clearframe/Favicons`); tabs and saved bookmarks of visited sites reuse the cache, unvisited hosts show a locally computed identity-color square instead, private tabs keep icons in memory only, and **Clear local browsing data** deletes the cache.
- Download contents and chosen destinations are handled locally. The in-app list describes only the current session; saved files remain at the user-selected destination, and Clearframe does not upload them or claim to scan them.
- The selected search provider stays in local macOS preferences. Clearframe sends search text only when the user submits it, to the selected provider’s normal HTTPS results page; it does not request remote suggestions while the user types. Direct website addresses bypass search.
- The new-tab AI catalog, task-specific editorial badges, and text filter are defined and evaluated locally. Its catalog version and checked date are bundled constants, not a remote-update claim. Selecting a card or official recommendation source performs ordinary HTTPS navigation. Clearframe does not append the current page, a generated prompt, an affiliate identifier, or tracking parameters.
- The first-run introduction stores one local completion boolean and reuses the existing local search-provider preference. It has no account, analytics event, identifier, purchase state, or remote onboarding service. Reopening the introduction does not clear browser data.
- The Settings reset closes all tabs and removes bookmarks, history, the in-app download list, restored-session records, recovery backups, per-site tracker-blocking exceptions, and WebKit cookies/caches/website storage. It deliberately keeps downloaded files, search and onboarding preferences, and the user-owned Optional AI key; active downloads must finish or be cancelled first.

### Extension local mode (validation artifact)

- The extension receives temporary access to the current page only after the user clicks its toolbar icon.
- Visible page text is extracted and analyzed inside the browser.
- No page text, URL, title, summary, or risk result is sent to a Clearframe server; this prototype has no server.
- Settings and at most one compact comparison snapshot are stored in the local browser profile.

### Optional AI mode

- The feature is off by default.
- The extension requests access only to `https://api.openai.com/*`; the native app connects directly through its optional provider.
- Page text is transmitted only when the user clicks **Improve with AI** or requests a non-local translation. Analysis sends the page title, hostname, declared source language, and at most 18,000 characters of extracted visible text. It does not send the full URL, query, fragment, cookies, form values, bookmarks, history, or other tabs. Translation sends only the displayed summary, source language, and target language.
- Requests use the user’s API key, ask the API not to store the response (`store: false`), and contain a random installation-scoped safety identifier rather than a name or email. Analysis uses a strict JSON schema; timeouts, refusals, incomplete output, and malformed output leave the valid local result visible.
- The extension key remains in local extension storage; the native app key is stored in macOS Keychain. Both approaches are acceptable only for a personal development prototype, not for a public product with a company-funded key.
- The macOS bundle includes a privacy manifest that conservatively declares optional provider text as user content used for app functionality, with tracking disabled and no tracking domains. It also declares Apple's `CA92.1` required reason for app-only `UserDefaults` preferences. The declaration does not replace a public privacy policy or App Store privacy answers.

## Not collected or transmitted by Clearframe

- browsing history or a passive URL feed on a Clearframe server (this prototype has no server);
- cookie values, passwords, form values, payment information, or download contents/destinations sent to a Clearframe service;
- advertising identifiers;
- data for sale to brokers or advertisers;
- hidden recommendation or affiliate clicks.
- AI-catalog searches, selections, or inferred interests sent to a Clearframe service.

## Safety limitations

Risk detection uses visible text and simple page facts. It can miss malicious pages and flag legitimate ones. A bare mention of TeamViewer, AnyDesk, or remote-access software no longer raises a signal by itself; the local heuristic requires nearby action language plus pressure, support, account, security, or payment context. That narrower rule can still misclassify content. Clearframe does not consult certificate details, download scanners, threat-intelligence feeds, domain age, redirect chains, or browser reputation services. The result must always be presented as “signals,” never as a security verdict.

Tracker blocking uses a small, first-party curated domain list enforced by WebKit's content-rule-list engine. It can miss trackers that are not on the list, including CNAME-cloaked or newly created tracking domains, and blocking a request can occasionally break a legitimate site feature that happened to load from a blocked domain—the per-site shield toggle turns blocking off for exactly that case. Clearframe cannot see or count what WebKit blocked, so the UI never reports a number, and a site loading normally with blocking on is not a safety verdict about that site.

AI summaries and translations can omit context, flatten uncertainty, or hallucinate. Page content can also contain indirect prompt injection. The prototype keeps AI read-only and gives it no page actions, account access, file access, email, browsing history, or tools. This limits the harm of a bad output but does not eliminate it.

The AI catalog is static editorial guidance. Sparse task badges are based on documented product focus and link to an official provider source; they are not universal/live rankings, comparative testing by Clearframe, endorsements, partnerships, paid placement, or guarantees of price or availability. Broad access labels are orientation only. Users leave Clearframe's local guide when they open a listed website; that provider then controls its own accounts, plans, service availability, data practices, and terms.

## Production requirements

Before a public launch:

1. Publish a plain-language privacy policy and complete browser-store privacy disclosures.
2. Move company-funded AI calls behind an authenticated, rate-limited proxy.
3. Redact obvious secrets and sensitive identifiers before remote processing.
4. Define retention, deletion, incident response, and subprocessors.
5. Add security review, dependency scanning, content-security-policy tests, and prompt-injection evaluation.
6. Give users a clear cloud-processing indicator and per-site disable control.
7. Separate paid recommendations from summaries, comparisons, and risk results.

The current provider request follows OpenAI's documented model/request and structured-output shapes: [GPT-5.6 Luna](https://developers.openai.com/api/docs/models/gpt-5.6-luna) and [Structured Outputs](https://developers.openai.com/api/docs/guides/structured-outputs). These links describe the API shape, not an endorsement or partnership.

Relevant implementation guidance: Chrome recommends `activeTab` as a privacy-preserving alternative to broad host access, and OWASP identifies indirect prompt injection and excessive agency as material LLM risks.

- Chrome `activeTab`: https://developer.chrome.com/docs/extensions/develop/concepts/activeTab
- Chrome extension privacy: https://developer.chrome.com/docs/extensions/develop/security-privacy/user-privacy
- OWASP prompt injection: https://genai.owasp.org/llmrisk/llm01-prompt-injection/
- OWASP excessive agency: https://genai.owasp.org/llmrisk/llm062025-excessive-agency/
