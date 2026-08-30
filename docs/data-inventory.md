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
| `clearframe.showAssistantPanel` | Whether a tab opens with the assistant panel showing |
| `<key>.lastKnownGood` · `<key>.unreadable` | Corruption-recovery copies of the four record keys above |

### Files on disk

`~/Library/Application Support/Clearframe/Favicons/<host>.png` — site icons, downscaled to 64px, capped at 256 KB each.
`~/Library/Application Support/Clearframe/Favicons/redirects.json` — which hosts redirect to which, learned from visits already made, so a bookmark saved at a redirecting address can find its icon. Hostnames only, no addresses or page titles.

### Keychain

**Nothing.** Clearframe stores no credential of any kind. It once held a user-supplied OpenAI key; that feature was removed on August 30, 2026 and the Keychain item with it.

### WebKit-managed

Cookies, caches, local and session storage, IndexedDB, and service workers, held in `WKWebsiteDataStore.default()` — the same storage any browser keeps for the sites a person visits. Private tabs use a non-persistent store that is discarded when the tab closes.

## 2. What leaves the Mac

Exactly four things. Nothing else.

**1. The pages the user browses.** Ordinary web requests to the sites they visit. Unavoidable — it is what a browser does.

**2. Search queries, on submit.** Sent to the provider the user chose (DuckDuckGo by default; Google, Bing, Brave Search, or Startpage if selected). **Nothing is sent while typing.** Address-bar suggestions are built only from history and bookmarks already on the Mac — no keystroke goes anywhere to produce them, and suggestions are silent entirely in private tabs.

**3. Up to four site-icon requests per visited page, usually one.** Fetched only during an actual visit, over an ephemeral session with no cookies, capped at 512 KB with a 5-second timeout. The hosts asked are the page's own origin and any host that page already loaded a resource from during the same visit — its own CDN, in practice. A host the page never used is never contacted, which is what makes a favicon service impossible rather than merely forbidden. **No third-party icon service is ever contacted** — a Google favicon endpoint would disclose the user's bookmark list to Google. Sites never visited are never contacted, and no icon is fetched speculatively for an imported bookmark. A redirect the visit already followed is recorded so the starting address can find the icon, which adds no request of any kind.

**That is the complete list.** There is no fourth entry. Clearframe contacts no AI provider, no analytics vendor, and no service of its own.

**Copy for AI is not a transfer.** Pressing it writes the page's extracted text to the Mac's clipboard — no request is made, and nothing leaves the machine by Clearframe's hand. Where it goes next is the person's own paste, into an application of their choosing, under that application's terms. Worth stating plainly, because it is a real exposure and it is theirs to control: the system clipboard is readable by every app on the Mac, and by their other Apple devices if Universal Clipboard is on.

## 3. What is never collected

- **No telemetry or analytics.** None. No usage counters, no crash reporting, no feature-flag service.
- **No accounts, sign-in, sync, or cloud backup.** There is no Clearframe server to hold anything.
- **No advertising identifiers**, no fingerprinting, no cross-site profile.
- **No browsing history sold or transmitted** to Clearframe — there is nowhere for it to go.
- **No page content uploaded because a page was opened.** Extraction runs only when the user clicks Analyze page.
- **No record of what tracker blocking blocked.** WebKit applies rules inside the page process and reports nothing back, so no count exists — which is why the interface shows state and never numbers.

## 4. User control

- **Clear local browsing data** (Settings) removes tabs, groups, history, bookmarks and folders, the download list, the favicon cache, per-site blocking exceptions, all WebKit site data, and the recovery copies. It deliberately keeps files already downloaded, the search choice, and onboarding state.
- **Per-site data removal** — Settings lists every site holding data, each with its own remove button; the same control appears in the address-bar site popover.
- **History can be disabled** so new visits are never recorded, and cleared independently.
- **Session restore can be disabled**, which also deletes the saved workspace.
- **Private tabs** keep site data in memory only and are excluded from history, session restore, and the disk favicon cache.

Private browsing limits, stated plainly: it isolates storage for that tab. It does not provide network anonymity, hide activity from websites or a network operator, or remove files the user chose to download.

## 5. Third parties

| Party | When | What they receive |
|---|---|---|
| The chosen search provider | On submitting a search | The query, under that provider's own terms |
| Websites visited | On visiting | Ordinary web request data, plus up to four cookie-free icon requests to the page's own origin or a host it already loaded from |

No other processor. No analytics vendor, no error-reporting service, no advertising network, no content delivery network of Clearframe's own.

Clearframe claims **no partnership or revenue arrangement** with any search provider or AI vendor.

## 6. Regulatory posture

Not legal advice, and no compliance assessment has been performed.

The structural position is unusually simple: for almost all of the data above, Clearframe never receives it. Bookmarks, history, tabs, and site icons exist only in the user's own macOS profile. There is no server, so there is no store to breach, no retention schedule to operate, and no export or deletion request that Clearframe could fulfil — because Clearframe holds nothing to export or delete. Deletion is fully in the user's hands through the controls in section 4.

As of August 30, 2026 there is no genuine transfer to a third party at all, beyond the sites the person visits and the search provider they chose. The AI path that used to exist was removed; what replaced it is a clipboard copy the person performs, sees in full beforehand, and directs themselves.

**Before public distribution**, `docs/privacy-and-safety.md` records the outstanding requirements: a plain-language privacy policy, redaction of sensitive identifiers before any remote processing, and an independent security review. None has been completed.

## Related

[privacy-and-safety.md](privacy-and-safety.md) · [content-blocking.md](content-blocking.md) · [ip-and-ownership.md](ip-and-ownership.md) · [macos-browser-foundation.md](macos-browser-foundation.md)
