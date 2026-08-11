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
- Bookmarks, their titled/emoji folder hierarchy, completed-visit history, and recent-tab URL/title metadata stay in the local Mac user profile. Legacy bookmarks without folder data remain visible as Unfiled. Users can remove bookmarks, clear or disable future history, and disable tab restoration; this phase has no bookmark account or sync service.
- Download contents and chosen destinations are handled locally. The in-app list describes only the current session; saved files remain at the user-selected destination, and Clearframe does not upload them or claim to scan them.
- The selected search provider stays in local macOS preferences. Clearframe sends search text only when the user submits it, to the selected provider’s normal HTTPS results page; it does not request remote suggestions while the user types. Direct website addresses bypass search.
- The new-tab AI catalog and its text filter are defined and evaluated locally. Selecting a card performs ordinary navigation to the provider's listed official HTTPS website. Clearframe does not append the current page, a generated prompt, an affiliate identifier, or tracking parameters.
- The first-run introduction stores one local completion boolean and reuses the existing local search-provider preference. It has no account, analytics event, identifier, purchase state, or remote onboarding service. Reopening the introduction does not clear browser data.

### Extension local mode (validation artifact)

- The extension receives temporary access to the current page only after the user clicks its toolbar icon.
- Visible page text is extracted and analyzed inside the browser.
- No page text, URL, title, summary, or risk result is sent to a Clearframe server; this prototype has no server.
- Settings and at most one compact comparison snapshot are stored in the local browser profile.

### Optional AI mode

- The feature is off by default.
- The extension requests access only to `https://api.openai.com/*`; the native app connects directly through its optional provider.
- Page text is transmitted only when the user clicks **Improve with AI** or requests a non-local translation.
- Requests use the user’s API key, ask the API not to store the response (`store: false`), and contain a random installation-scoped safety identifier rather than a name or email.
- The extension key remains in local extension storage; the native app key is stored in macOS Keychain. Both approaches are acceptable only for a personal development prototype, not for a public product with a company-funded key.

## Not collected or transmitted by Clearframe

- browsing history or a passive URL feed on a Clearframe server (this prototype has no server);
- cookie values, passwords, form values, payment information, or download contents/destinations sent to a Clearframe service;
- advertising identifiers;
- data for sale to brokers or advertisers;
- hidden recommendation or affiliate clicks.
- AI-catalog searches, selections, or inferred interests sent to a Clearframe service.

## Safety limitations

Risk detection uses visible text and simple page facts. It can miss malicious pages and flag legitimate ones. It does not consult certificate details, download scanners, threat-intelligence feeds, domain age, redirect chains, or browser reputation services. The result must always be presented as “signals,” never as a security verdict.

AI summaries and translations can omit context, flatten uncertainty, or hallucinate. Page content can also contain indirect prompt injection. The prototype keeps AI read-only and gives it no page actions, account access, file access, email, browsing history, or tools. This limits the harm of a bad output but does not eliminate it.

The AI catalog is static editorial guidance, not a live ranking, endorsement, partnership, or guarantee of price or availability. Users leave Clearframe's local guide when they open a listed website; that provider then controls its own accounts, plans, service availability, data practices, and terms.

## Production requirements

Before a public launch:

1. Publish a plain-language privacy policy and complete browser-store privacy disclosures.
2. Move company-funded AI calls behind an authenticated, rate-limited proxy.
3. Redact obvious secrets and sensitive identifiers before remote processing.
4. Define retention, deletion, incident response, and subprocessors.
5. Add security review, dependency scanning, content-security-policy tests, and prompt-injection evaluation.
6. Give users a clear cloud-processing indicator and per-site disable control.
7. Separate paid recommendations from summaries, comparisons, and risk results.

Relevant implementation guidance: Chrome recommends `activeTab` as a privacy-preserving alternative to broad host access, and OWASP identifies indirect prompt injection and excessive agency as material LLM risks.

- Chrome `activeTab`: https://developer.chrome.com/docs/extensions/develop/concepts/activeTab
- Chrome extension privacy: https://developer.chrome.com/docs/extensions/develop/security-privacy/user-privacy
- OWASP prompt injection: https://genai.owasp.org/llmrisk/llm01-prompt-injection/
- OWASP excessive agency: https://genai.owasp.org/llmrisk/llm062025-excessive-agency/
