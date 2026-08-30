# Durable project context

**Status:** August 2026. This file records decisions that should survive beyond any one conversation or development tool.

The companion [Clearframe strategy and product memory](clearframe-strategy.md) is the authoritative plain-language vision, non-goals, sequencing, and continuity brief. The trusted GitHub repository is [romanlucian/Ki-browser](https://github.com/romanlucian/Ki-browser).

## Product decision

Clearframe is a real, standalone, macOS-first browser for ordinary users. Its interface is English-first, while Analyze Page must support source-language pages across languages. The delivered and installed version owns its native window and currently renders pages with SwiftUI + WebKit. The earlier Chromium side-panel extension remains useful validation work, but it is not the current product and must not be presented as the finished browser.

The selected migration path for a future Chromium-based Clearframe is the official Chromium Embedded Framework (CEF), hosted behind a narrow Objective-C++ bridge while retaining SwiftUI and `ClearframeCore`. The isolated scaffold at `chromium/cef-spike` is architecture validation only: it is not linked into the current app, does not make the installed app Chromium, and is not a full Chromium source fork. Keep WebKit as the working baseline until the CEF build meets documented parity, privacy, security-update, and distribution gates.

The focused promise is to help people meet an unfamiliar page with the AI they already use: pull the readable article out of the page, show any visible risk signals, and hand the text over cleanly. Clearframe does not summarize a page, rank its sentences, or judge what it says. It is not a generic Chrome clone, a truth engine, or an antivirus product.

The primary user promise is **“Clearframe makes the AI world simple for ordinary people.”** Clarity outranks feature count. The magic first minute should begin from a recognizable goal, show a small useful set of AI paths, and get an open page ready for the AI the person already uses. The current AI home and Analyze Page are the foundation. Analyze Page shows what the page is, any visible risk signals, and a Copy for AI button that puts the extracted article on the clipboard — with the exact payload visible first, because the honest part of this product is showing somebody what they are about to hand over.

The quality objective is “fast and calm even when the web is heavy.” This is a measurable design goal, not permission to claim Clearframe is the world's lightest or fastest browser without evidence. Radical clarity, high craft, ordinary users, trust before monetization, and real-person testing are standing principles.

Voice is an additional primary interface, not a replacement for visual search or cited visual answers. The first voice phase is explicit, on-device dictation into the visible search/address field. There is no wake word, background listening, automatic submission, or autonomous transaction.

## AI and privacy decisions

- Extraction and risk signals work locally without an account or API key, because there is no account or API key: Clearframe calls no AI service and stores no credential for one.
- Analyze Page preserves the source language. Deterministic coverage for risk phrases and sentence segmentation includes English, Romanian, French, and Simplified Chinese; it does not imply equal quality in every language.
- **No page text leaves the Mac.** Not by default, not after a click, not at all. The only way a page reaches an AI is the person copying it and pasting it somewhere themselves.
- Visible page text is extracted only when the user requests analysis.
- The readable text Copy for AI produces is the page's own words and never contains a character the page lacks. Sentence splitting must stay identical in both runtimes, enforced by `segmentationCases` in the shared contract, because the media-boilerplate filter counts whole sentences and a split that differs silently disables it in one runtime. Terminator coverage is `. ! ? 。 ！ ？ । ॥ ۔ ؟ ։`; Thai is not covered, having no terminator character to recognise. A full stop does not end a sentence before a lowercase letter or a digit, after a lone initial such as `U.S.`, or after an abbreviation listed for the page's declared language.
- Copy for AI is the only path by which a page's text leaves Clearframe, and it leaves via the person's own clipboard, on their own click, after they have been shown the complete payload. Clearframe makes no network request with it. The clipboard is shared with other applications and, if the person has Universal Clipboard on, with their other Apple devices; the card says so.
- Browsing history is never sold. Current bookmarks and nested emoji-labeled folders, capped history, and recent-tab metadata stay in the local Mac user profile and have user controls. Legacy flat bookmarks migrate to the Unfiled location without being discarded.
- Page content is untrusted. The assistant remains read-only and receives no cookies, form values, passwords, unrelated tabs, or browsing-history feed.
- The new-tab AI guide is a static catalog bundled with the app. Filtering is local, cards use direct official HTTPS destinations, and Clearframe does not attach page content, prompts, affiliate tags, or tracking parameters. A tool's card is drawn with the mark the browser already captured when that tool was opened, under the same rule as every other site icon: no logo ships with the app, nothing is fetched for a tool the user has never visited, and an unopened tool keeps its designed monogram.
- A selected task may show a small number of sourced editorial badges such as Best Overall, Best Value, or Easiest to Start. The visible version and checked date are manual, broad access labels avoid exact pricing, and the badge rationale links to an official provider source. This is not universal ranking, product testing by Clearframe, provider partnership, availability guarantee, paid ordering, or automatic updating. Follow [the editorial policy](ai-catalog-editorial.md).

## Business direction

The intended sequence was a free useful browser, optional AI Pro for heavy usage, business plans with administration and approved model routing, and search revenue sharing only after meaningful scale exists. **That Pro thesis assumed Clearframe would be the one providing the AI.** It no longer is, and steps two and three of that sequence do not survive the change: a provider the user brings themselves bears the inference cost, sets the limits, and cannot be metered, routed or governed by Clearframe. Either the monetization plan is rebuilt around something Clearframe actually owns, or it is consciously abandoned — it must not be left standing as a story the architecture cannot support. Transparent intent-based partner recommendations may be explored later, but they must be clearly labeled and must never alter risk signals or extraction invisibly.

Product sequencing is Developer ID signing and notarization first — nobody outside this Mac can open the app until that is done, so every other measurement is guesswork — then observed user sessions, then extraction quality, then whatever reads that extraction. This is a direction, not a revenue guarantee.

As of August 14, 2026, the repository contains automated quality evidence but no completed observed-user-session record. Do not imply activation, retention, referral, or usability validation until consented sessions are actually run and aggregate evidence is recorded. Recruitment counts and decision thresholds have one owner: [go-to-market.md](go-to-market.md).

The initial launch approach is intentionally lean and zero-budget. Clearframe is globally positioned and English-first, while the first acquisition/validation wedge is creators overwhelmed by AI: photographers, designers, video creators, and creative freelancers. Use the founder's authentic visual/photography practice for clear workflow demonstrations, not borrowed authority or generic crowded tool-list videos. Prioritize YouTube workflow case studies, derived Shorts/TikTok, personal-network and creative-community testers, direct observation, honest GitHub build notes, and learning from activation, seven-day return, and voluntary referrals. Do not use fake claims, spam, implied partnerships, premature paid advertising, or guaranteed-growth language. The practical 30/60/90-day plan and stop rules are in [go-to-market.md](go-to-market.md).

Building an independent search index is a separate, capital-intensive future business. It is not part of the current browser MVP. DuckDuckGo is the initial search default, but users can visibly choose DuckDuckGo, Google, Bing, Brave Search, or Startpage from the address bar or Settings. The choice is stored locally, and no provider partnership or revenue agreement is claimed.

## Scope boundaries

Two-source comparison was removed on August 25, 2026 and should not be rebuilt on word counting. It saved one analyzed page, then reported how many words it shared with a second. Measured through the real engine, two Wikipedia articles on the same subject scored 4% and two unrelated ones scored 2%, so the number could not tell the cases apart. Comparing full page text with cosine similarity fixes that much — 74% against 11% — but not the thing the feature is for:

    "Turnout rose to forty percent"   vs  "Turnout fell to twenty percent"    80% similar
    "The council approved the repair" vs  "The council rejected the repair"   82% similar
    "the drug reduced symptoms"       vs  "the drug increased symptoms"       90% similar

Counting words does not merely fail to notice disagreement; it scores disagreement as agreement, because a contradiction shares every word but one. Comparing sources means comparing claims, and that needs something that knows "rose" and "fell" are opposites. Local analysis has no semantics and never will.

If it returns, it belongs to whatever model reads the page, and that model should quote the conflicting sentences rather than write prose about them. Note that Apple's on-device model does not support Romanian, so that route would not cover the founder's own daily reading.


Local page judgment — the gist, the key points, the candidate claims and the term-frequency scorer behind them — was removed on August 30, 2026 and must not be rebuilt on word counting. The scorer ranked a sentence by how many of the page's most repeated words it contained, divided by its length, plus a bonus for matching the title or appearing early. That is lexical centrality. It is not importance, and the difference is visible on real pages:

    Britannica, "Artificial intelligence"
      most repeated words   ai(54) intelligence(27) language(23) artificial(22)
      #1  score 1.791       "Artificial general intelligence (AGI), applied AI, and cognitive…"
      #2  score 1.678       the site's own NAVIGATION MENU
      #3  score 1.626       "Artificial general intelligence (AGI), or strong AI—that is…"

The menu won second place because it contains the words *intelligence*, *artificial* and *technology*. The scorer has no concept of a menu; it counted words.

The gist was worse than the ranking, and worse by construction: it was three separately-chosen sentences joined by a space. Nothing checked that the second followed from the first, so it routinely opened with a dangling reference — "These advances in software and operating systems were matched by…" — or welded a headline onto a paragraph with no punctuation between them. Three independent reviews called it a category error: a summary has to be *written*, and choosing three existing sentences never produces one.

Removed with it: the four stopword tables, the 39-term claim vocabulary, the thirteen-pair Plain English table (find-and-replace wearing the name of simplification), the optional OpenAI provider and its Keychain key storage, and Evidence Mode's exact-match highlighting, which had no reachable entry point once key points were gone. `docs/local-analysis-evidence-defects.md` went too; its still-live segmentation rules are in `CLAUDE.md` and the page-intelligence contract, and git holds the rest.

**What would bring page understanding back:** a model that actually reads. The shape that keeps the honesty is the model returning quotes it says are from the page, and Clearframe verifying each one by substring test before showing it — grounding checked rather than assumed. Nothing about that requires the deleted scorer.

A programmer-focused browsing workspace is documented as a separate future concept. It may connect documentation, GitHub, code explanation, research, and VS Code workflows, but it must not redirect the current general-audience browser or create a second browser product now.

A later Windows client may reproduce the language-neutral page-intelligence contract, but the current native SwiftUI UI is intentionally macOS-specific. The macOS Chromium migration work does not select a Windows UI or packaging stack.

Do not switch rendering engines now. CEF remains a future gated path for demonstrated cross-platform or Chromium-extension needs, after parity, security-update, privacy, licensing, packaging, and distribution requirements are met.

## Delivered version-1 capabilities

- Standalone native windows with startup activation and address-field focus. Each window keeps its own tabs and selection while sharing bookmarks, history, downloads, site icons, tracker rules, and settings; menu commands act on the window in front. A tab can be dragged out of the strip, up or down, into a window of its own, carrying its live web view so the page keeps its scroll position and back/forward list. Only the first window restores the saved session, and only that window's tabs are written back — a torn-off window's tabs are not restored after a relaunch.
- Explicit on-device voice-input shell with visible status and review-before-submit behavior.
- Independent tabs, safe close/teardown, safe popup routing, external HTTP/HTTPS opening, tab keyboard commands, and ephemeral private tabs. A private window (⇧⌘N) opens blank, makes every tab in it private, restores no session and writes none, and has no way to open an ordinary tab.
- Local restoration of up to 12 recent regular-tab URLs/titles with lazy loading, corruption recovery, and an opt-out; private tabs are excluded.
- Back, forward, home, reload, stop, address/search, progress, HTTPS indication, and clear loading/offline/error states.
- Default-on tracker blocking against a small, first-party curated domain list, enforced locally by WebKit's content-rule-list engine, with an address-bar shield control, a Settings switch, per-site exceptions, and state-only status text with no per-page or running block counts (see [content-blocking.md](content-blocking.md)).
- A visible search-provider chooser with a locally persisted selection; direct website addresses bypass search.
- A polished native new-tab AI guide organized around Ask & Learn, Write, Research, Create Images, Create Videos, Translate, and Code, with a local filter, transparent task-specific editorial badges, a visible catalog checked date/version, broad access labels, recommendation source links, and direct official-site cards. Gemini's image guidance and the separate Veo and Seedance video cards use cautious, provider-controlled availability language. Activating a card navigates the current tab, exposes the exact destination immediately, and shows provider-specific loading feedback. The page states plainly that Clearframe has no relationship with the companies it lists and that the names belong to them, which is also the notice Midjourney and Canva ask for in return for being named. A tool that has been opened is drawn with the icon that visit captured, falling back to its monogram.
- A three-step, locally completed first-run introduction covering the product promise, five-provider search choice, local/cloud privacy boundary, AI home, and the user-triggered Analyze page workflow. It can be reopened from Settings without clearing tabs or data and contains no paywall or purchase flow.
- User-confirmed downloads with an obvious toolbar panel, empty state, destination/status, cancel, reveal, clear-finished, and Open Downloads Folder controls.
- A visible-by-default native bookmarks bar below navigation with top-level folders that always render one emoji-plus-name label (long names truncate rather than becoming icon-only), Unfiled links, recursive folder menus, horizontal scrolling, fixed overflow access, and a locally persisted show/hide control. The address field's lock/globe chip exports the current safe web URL; dropping it on bar space saves to Unfiled and dropping it on a visible folder files it there. Existing bookmarks can be dragged to visible folders, with one-record move/no-duplicate semantics and the Move menu retained for keyboard access. Standard macOS secondary-click/Control-click menus add the current page, create root folders or nested subfolders, and open the full-page bookmarks home; the More and Page menus provide accessible alternatives, including ⌘⌥B for the same full-page home. The toolbar's Library button keeps a separate quick popover for fast lookups.
- A unified single-row dark chrome with inline traffic lights in the tab strip, one toolbar/address-pill row, and per-site icons captured only while visiting a site, from the page's own origin or a host that page already loaded something from during the same visit (its own CDN, in practice), cached locally, memory-only in private tabs, cleared by the browsing-data reset, with a locally derived identity-color square for unvisited hosts—never a third-party icon service, which no page ever loads from and so cannot be reached by this rule at all.
- A full-page bookmarks home (⌘⌥B or the bookmarks bar) with folder cards showing rolled-up bookmark/subfolder counts, search across bookmarks and folder titles, and drill-down navigation. History is a separate destination on ⌘Y, grouped by day, matching where every mainstream Mac browser puts it.
- Local bookmark organization with emoji-labeled nested folders, safe legacy migration, move/rename/delete controls, and searchable capped history with remove, clear, and disable controls.
- User-triggered Analyze Page: the source, a reading-time estimate, visible risk signals, and Copy for AI. Copy shows the character count and the complete payload before it copies anything, and says plainly that the clipboard is shared with other apps and with Universal Clipboard. Two filters keep interface noise out of that text — see the extraction-quality regression gate below.
- A structure notice: Analyze Page recognises listing and index pages, explains that they list many articles rather than one text, and offers an explicit Analyze anyway.
- User-confirmed removal of tabs, history, bookmarks, in-app download metadata, per-site tracker-blocking exceptions, WebKit cookies/caches/website storage, workspace records, and recovery backups without deleting saved download files or general preferences.
- Visible page dialogs and media permission prompts, WebKit renderer-termination state, same-document URL/title synchronization, and local last-known-good persistence recovery.
- Profiles, each owning its bookmarks, history, saved session, site icons, per-site tracker exceptions and — through a separate `WKWebsiteDataStore` — its logins, so two profiles signed into the same site do not share a session. Downloads, the search choice and the WebKit switches are shared. A window belongs to one profile for life and choosing a profile opens a window in it; a tab cannot be dragged across that line. The profile that predates the feature keeps the application's original stores and cannot be deleted.
- Standard Mac menus: File (new tab, new window, new private window, new empty tab group, open a local file, close window, save the page as a web archive, share its address through the system picker, export it as a PDF, print), View (reload, stop, zoom), History (recent pages, one entry per page, plus back, forward, and reopen closed tab), and Bookmarks (the bar's folders and links). Opening a local file is a separate, person-driven path through an open panel; `WebURLPolicy` still refuses local schemes everywhere else, and a local page enters neither history nor the saved session.
- A locally built app bundle at `dist/Clearframe.app`; it includes an icon and privacy manifest and uses the hardened runtime with an ad hoc local signature. It is not Developer ID signed or notarized.

## Extraction quality regression gate

Complex news pages can expose embedded media-player controls and accessibility boilerplate as text. `zf.ro` is the standing regression case. Two filters keep it out, and neither alters a sentence: one drops a sentence when known control phrases cover most of it, the other drops any sentence the page repeats three or more times, which needs no vocabulary and so recognises a player in any language. An earlier version deleted those phrases from inside ordinary prose and emitted text the page did not contain; never reintroduce editing in place. Coverage is the shared contract's `boilerplateCases` plus an installed-app live check on `https://www.zf.ro/`; preserve both.

## Remaining release gaps

This is a practical MVP, not a Chrome/Safari-scale production browser. Remaining work includes broader navigation and hostile-page QA, bookmark/folder reordering, import from other browsers, and sync, granular per-site data controls, comprehensive site permissions and certificate UI, a security-reviewed password/import system, persisted/resumable download history and scanning, crash reporting and relaunch recovery beyond the delivered WebKit-process error state, updater infrastructure, accessibility QA, sensitive-identifier redaction, independent security review, Developer ID signing, notarization, default-browser registration QA after signed installation, and public distribution work.

## Source license

The repository is licensed under the GNU Affero General Public License v3.0 (`LICENSE`, verbatim upstream text). This was a deliberate maintainer decision on August 14, 2026, not an inferred default. It keeps the build-in-public narrative workable while requiring that a network-deployed modified version also offer its corresponding source. The maintainer retains copyright and may issue separate commercial terms. Do not relicense, add per-file headers, or accept outside contributions without deciding a contribution-terms policy first.
