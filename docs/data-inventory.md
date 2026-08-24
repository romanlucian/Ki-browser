# Data inventory

**Status:** August 20, 2026. A complete record of what Clearframe stores, where it stores it, and what leaves the user's Mac. Read from the source, not from marketing copy.

**Purpose.** Privacy claims are only worth what they can be verified against. This is the one page that answers "what data does this application touch" for a user, an investor, a security reviewer, or a buyer — without them having to read the code.

**The short version.** Clearframe has no server, no account system, and no telemetry. Almost everything it stores stays in the user's own macOS profile. Four things leave the Mac, all of them either initiated by the user or unavoidable for browsing to work, and each is listed in section 2.

## 1. Stored on the user's Mac

### Preferences and records — `UserDefaults`, standard suite

| Key | Contents |
|---|---|
| `clearframe.bookmarks.v1` | Saved bookmarks: title, address, creation date, folder |
| `clearframe.bookmarkFolders.v2` | Folder titles, icons, tints, hierarchy |
| `clearframe.history.v1` | Visit history: title, address, timestamp. **Capped at 500 entries** |
| `clearframe.workspace.v1` | Open tabs (address and title only), selection, tab groups |
| `clearframe.restoreTabs` · `clearframe.reloadRestoredTabs` · `clearframe.saveHistory` · `clearframe.showBookmarksBar` | Preference switches |
| `clearframe.searchEngine` | Chosen search provider |
| `clearframe.contentBlocking.enabled` · `.disabledHosts` | Tracker blocking state and per-site exceptions |
| `clearframe.onboarding.completed.v1` | First-run completion flag |
| `clearframe.remoteAIEnabled` · `clearframe.openAIModel` · `clearframe.openAIModelCustomized` | Optional AI settings — **never the key itself** |
| `clearframe.safetyIdentifier` | A random per-installation identifier, generated locally, sent to OpenAI **only** if the user enables Optional AI. Not a name, email, or device identifier |
| `<key>.lastKnownGood` · `<key>.unreadable` | Corruption-recovery copies of the four record keys above |

### Files on disk

`~/Library/Application Support/Clearframe/Favicons/<host>.png` — site icons, downscaled to 64px, capped at 256 KB each.
`~/Library/Application Support/Clearframe/Favicons/redirects.json` — which hosts redirect to which, learned from visits already made, so a bookmark saved at a redirecting address can find its icon. Hostnames only, no addresses or page titles.

### Keychain

One item: the user's own OpenAI API key. Service `com.clearframe.browser.prototype`, account `openai-api-key`, accessible after first unlock, this device only. **Clearframe ships no key of its own and never has.**

### WebKit-managed

Cookies, caches, local and session storage, IndexedDB, and service workers, held in `WKWebsiteDataStore.default()` — the same storage any browser keeps for the sites a person visits. Private tabs use a non-persistent store that is discarded when the tab closes.

## 2. What leaves the Mac

Exactly four things. Nothing else.

**1. The pages the user browses.** Ordinary web requests to the sites they visit. Unavoidable — it is what a browser does.

**2. Search queries, on submit.** Sent to the provider the user chose (DuckDuckGo by default; Google, Bing, Brave Search, or Startpage if selected). **Nothing is sent while typing.** Address-bar suggestions are built only from history and bookmarks already on the Mac — no keystroke goes anywhere to produce them, and suggestions are silent entirely in private tabs.

**3. Up to four site-icon requests per visited page, usually one.** Fetched only during an actual visit, over an ephemeral session with no cookies, capped at 512 KB with a 5-second timeout. The hosts asked are the page's own origin and any host that page already loaded a resource from during the same visit — its own CDN, in practice. A host the page never used is never contacted, which is what makes a favicon service impossible rather than merely forbidden. **No third-party icon service is ever contacted** — a Google favicon endpoint would disclose the user's bookmark list to Google. Sites never visited are never contacted, and no icon is fetched speculatively for an imported bookmark. A redirect the visit already followed is recorded so the starting address can find the icon, which adds no request of any kind.

**4. Optional AI, only after an explicit action.** Off by default. Requires the user to supply their own OpenAI key. When they click Improve with AI or request a translation, the request contains the page title, hostname, declared language, and at most 18,000 characters of extracted visible text — plus the random installation identifier from section 1.

That request **omits** the full URL, query string, fragment, cookies, form values, passwords, other tabs, and browsing history. It sets `store: false`. If it fails, the local result stays on screen.

## 3. What is never collected

- **No telemetry or analytics.** None. No usage counters, no crash reporting, no feature-flag service.
- **No accounts, sign-in, sync, or cloud backup.** There is no Clearframe server to hold anything.
- **No advertising identifiers**, no fingerprinting, no cross-site profile.
- **No browsing history sold or transmitted** to Clearframe — there is nowhere for it to go.
- **No page content uploaded because a page was opened.** Extraction runs only when the user clicks Analyze page.
- **No record of what tracker blocking blocked.** WebKit applies rules inside the page process and reports nothing back, so no count exists — which is why the interface shows state and never numbers.

## 4. User control

- **Clear local browsing data** (Settings) removes tabs, groups, history, bookmarks and folders, the download list, the favicon cache, per-site blocking exceptions, all WebKit site data, and the recovery copies. It deliberately keeps files already downloaded, the search choice, onboarding state, and the user's API key.
- **Per-site data removal** — Settings lists every site holding data, each with its own remove button; the same control appears in the address-bar site popover.
- **History can be disabled** so new visits are never recorded, and cleared independently.
- **Session restore can be disabled**, which also deletes the saved workspace.
- **Private tabs** keep site data in memory only and are excluded from history, session restore, and the disk favicon cache.
- **Optional AI can be turned off and the key deleted** from Settings.

Private browsing limits, stated plainly: it isolates storage for that tab. It does not provide network anonymity, hide activity from websites or a network operator, or remove files the user chose to download.

## 5. Third parties

| Party | When | What they receive |
|---|---|---|
| The chosen search provider | On submitting a search | The query, under that provider's own terms |
| Websites visited | On visiting | Ordinary web request data, plus up to four cookie-free icon requests to the page's own origin or a host it already loaded from |
| OpenAI | Only if Optional AI is enabled **and** the user acts | Page title, host, language, ≤18,000 characters of text, random installation identifier |

No other processor. No analytics vendor, no error-reporting service, no advertising network, no content delivery network of Clearframe's own.

Clearframe claims **no partnership or revenue arrangement** with any search provider or AI vendor.

## 6. Regulatory posture

Not legal advice, and no compliance assessment has been performed.

The structural position is unusually simple: for almost all of the data above, Clearframe never receives it. Bookmarks, history, tabs, and site icons exist only in the user's own macOS profile. There is no server, so there is no store to breach, no retention schedule to operate, and no export or deletion request that Clearframe could fulfil — because Clearframe holds nothing to export or delete. Deletion is fully in the user's hands through the controls in section 4.

The one genuine transfer to a third party is Optional AI, which is off by default, requires the user's own credential, and sends a disclosed payload only on an explicit click.

**Before public distribution**, `docs/privacy-and-safety.md` records the outstanding requirements: a plain-language privacy policy, redaction of sensitive identifiers before any remote processing, and an independent security review. None has been completed.

## Related

[privacy-and-safety.md](privacy-and-safety.md) · [content-blocking.md](content-blocking.md) · [ip-and-ownership.md](ip-and-ownership.md) · [macos-browser-foundation.md](macos-browser-foundation.md)
