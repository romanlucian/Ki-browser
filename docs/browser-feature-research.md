# Browser feature research and gap analysis

**Status:** August 19, 2026; sections 1 and 2 re-audited August 21, 2026. A snapshot, not a roadmap. It records what Clearframe has, what mainstream browsers have that it does not, and which gaps are worth closing. Read it with [clearframe-strategy.md](clearframe-strategy.md), which decides what Clearframe is *for*; this file only supplies evidence.

## Why this file exists

Features were going in reactively. This is the systematic pass that replaces that: one audit of Clearframe's own source, and three competitor studies. Without it the same research gets re-run every few weeks.

This repository is edited by more than one session, often within the same week, so sections 1 and 2 — the parts that describe what Clearframe currently has — go stale fast and need periodic re-checking against source. Sections 3 through 8 describe Chromium internals, WebKit behavior, and competitor products, none of which change when this codebase does, so they are not re-audited here.

**How it was produced.** Four subagents on August 19, 2026: one read this repository's source directly, three researched Safari, Chrome, and the challenger browsers. The Chrome study lost its web-search budget and pivoted to reading Chromium's own source on `googlesource.com`, which produced better ground truth than search would have.

**Re-audit, August 21, 2026.** One session re-checked every capability sections 1 and 2 named, directly against `macos/ClearframeBrowser/Sources/`, by reading the relevant code rather than trusting a menu entry. Several capabilities section 2 recorded as absent on August 19 had shipped in the two days since; the two defects it recorded were confirmed fixed and removed. Sections 3–8 were not touched and were not re-verified this pass.

**Confidence conventions used throughout.** *Verified* means read live from primary source this session. *Recalled* means established knowledge that was not re-confirmed and should be checked before anyone depends on it. Anything unmarked in the Clearframe sections was read from this repository's source and is verified by construction.

## 1. Clearframe today — corrections to common assumptions

Several capabilities are frequently assumed missing and are in fact shipped. Verified in source:

| Assumed missing | Reality |
|---|---|
| Find on page | Shipped — ⌘F / ⌘G / ⇧⌘G, with an honest no-match state |
| Page zoom | Shipped — ⌘+ / ⌘− / ⌘0, plus pinch magnification |
| Print | Shipped — ⌘P |
| Default-browser registration | Shipped — a Settings section with live status |
| Full-page history view | Shipped — inside the bookmarks home |
| Address suggestions | Shipped — local only, from history and bookmarks, no network |
| Per-site website-data removal | Shipped — Settings and the site-information popover |
| Tab groups, tab width compression | Shipped |
| Reopen closed tab | Shipped — ⇧⌘T, `BrowserWorkspace.reopenClosedTab()` |
| ⌘1–9 tab selection | Shipped — ⌘1–⌘8 pick that tab, ⌘9 picks the last one however many are open, matching Safari rather than counting to nine |
| Duplicate tab | Shipped — Tabs menu, `duplicateSelectedTab()` |
| Pin tab | Shipped — from a tab's own context menu, not a menu-bar shortcut |
| Tab drag-reorder | Shipped — `BrowserWorkspace.moveTab(_:toIndex:)` |
| Multiple windows | Shipped — ⌘N, plus ⌘⇧N for a private window |
| Profiles | Shipped — a Profiles menu backed by `ProfileStore` |
| Tab tear-off | Shipped — drag a tab out and it opens in a window of its own (`TornWindowDrag.swift`) |
| Bookmarks-bar reordering | Shipped — `BrowserDataStore.moveBookmark(_:toIndex:)` |
| Share sheet | Shipped — File ▸ Share Page…, hands only the page's address to `NSSharingServicePicker` (`PageFileCommands.share`) |

Anyone planning work should check this table first. Documentation has drifted from the code more than once.

## 2. Verified absences

Confirmed absent by source search, grouped by why they are absent. Re-checked against source August 21, 2026; several items present here on August 19 have since shipped and moved to section 1 above.

**Structural.** Reader mode · per-site permission centre (media capture is always `.prompt` and never remembered — verified again at `BrowserSession.webView(_:requestMediaCapturePermissionFor:...)`; no geolocation or notification delegate exists) · per-site zoom memory (verified deliberate: `BrowserSession.pageZoom`'s doc comment says a site's zoom is "deliberately not stored" between tabs or launches) · startup-page options beyond tab restore (Settings only offers restore-tabs toggles, no configurable homepage or new-tab address) · appearance and theme settings · accessibility settings · localization (no `.lproj`, English-only strings) · proxy settings · tab hibernation · screenshot capture · keyboard-shortcut customization · certificate-details UI · crash reporter · updater.

**Downloads specifically.** No resume or pause (`WKDownloadDelegate`'s `resumeData` is received on failure but never used to resume), no persistent history across launches (`DownloadCenter.items` is in-memory only), no byte progress, no quarantine or reputation check.

**Commercially significant.** No bookmark import or export. This is the single largest adoption blocker: a browser that cannot bring a person's bookmarks with them is not switchable. Section 3 specifies the fix completely.

**Not possible with public API — do not attempt again without re-checking the SDK.** Mute tab and the audio indicator that makes muting useful: the public WebKit headers carry no mute property and no `isPlayingAudio`, both of which live behind private API, and the only audio-related public knob is `mediaTypesRequiringUserActionForPlayback`, which gates autoplay rather than sound. Injected JavaScript could silence `<video>` and `<audio>` elements, but it leaks on Web Audio and any page can un-mute itself, and no public API can say *which* tab is making noise — so muting would be guesswork. Picture-in-picture the same way: `allowsPictureInPictureMediaPlayback` is declared `API_AVAILABLE(ios(9.0))` with no macOS equivalent, and on this platform WebKit's own video controls already offer it, so there is nothing to add. Both were verified by compiling against the macOS SDK on August 21, 2026, not inferred.

**Deliberately excluded, and should stay excluded.** Extensions (WebKit has no host for Manifest V3; the CEF scaffold exists as a future gate, not a plan) · passwords and autofill (blocked behind a security review that has not happened) · search suggestions (they would send every keystroke to a search engine; the local-only completion is the better product) · crypto wallets, ad networks, and agentic page actions (rejected in strategy).

The August 19 audit's "two defects found" section is gone: both were confirmed fixed on re-audit. ⌘W's double binding is gone — `ClearframeBrowserApp.swift` now explicitly clears AppKit's default window-list command group (`CommandGroup(replacing: .singleWindowList) {}`) with a comment explaining why, so ⌘W closes only a tab and ⇧⌘W closes a window. And the `BrowserWorkspace.swift` comment describing a tab picked "from ⌘1-⌘9" is no longer a stale claim — that shortcut is now wired up in `ClearframeBrowserApp.swift` (see the ⌘1–9 row in section 1).

## 3. Bookmark import — complete specification

Enough detail to implement without further research. Chromium facts verified from source this session.

### File locations (macOS)

```
~/Library/Application Support/Google/Chrome/Default/Bookmarks
~/Library/Application Support/BraveSoftware/Brave-Browser/Default/Bookmarks
~/Library/Application Support/Microsoft Edge/Default/Bookmarks
```

Additional profiles are `Profile 1`, `Profile 2`, … — sequential folder names that do **not** match the profile's display name. Map folder to display name through the sibling `Local State` JSON at `profile.info_cache.<folder>.name` (*recalled*).

macOS has **no `User Data` intermediate folder**. That path segment exists only on Windows, and carrying it over is a common porting bug.

### Chromium JSON schema

Verified from `components/bookmarks/browser/bookmark_codec.cc` and `.h`.

```
{ "checksum": "<md5 hex>", "checksum_sha256": "<sha256 hex>",
  "roots": { "bookmark_bar": {…}, "other": {…}, "synced": {…} },
  "version": 1 }
```

`synced` is the key Chrome's interface labels **"Mobile bookmarks"** — retained for historical reasons, per the source.

Every node carries: `id` (session-local integer, not stable) · `guid` (stable UUID — the identity to preserve) · `name` (title, for folders and bookmarks alike) · `type` (`"url"` or `"folder"`) · `url` (url nodes only) · `date_added` · `date_modified` · `date_last_used` · `children` (folders only) · `meta_info` (optional string dictionary).

**Chrome does not validate its own checksum on load.** `BookmarkCodec::Decode()` was read directly: it reconstructs the tree with no comparison, no rejection, no warning. Checksums are computed only on save. An importer therefore never needs to reproduce Chrome's hashing.

### Timestamps

Verified from `base/time/time.h`. Chromium timestamps are **microseconds since 1601-01-01 UTC**:

```
kMicrosecondsFromWindowsToUnixEpoch = 11_644_473_600_000_000

unixSeconds = (value / 1_000_000) - 11_644_473_600
```

A `0` means "not set" — treat as absent, not as the year 1601.

### Netscape bookmark HTML

Verified verbatim from `chrome/browser/bookmarks/bookmark_html_writer.cc`. This is what **every** browser exports and imports — Chrome, Safari, Firefox, Edge, Brave — which makes it the highest-value single format to support.

```html
<!DOCTYPE NETSCAPE-Bookmark-file-1>
<META HTTP-EQUIV="Content-Type" CONTENT="text/html; charset=UTF-8">
<TITLE>Bookmarks</TITLE>
<H1>Bookmarks</H1>
<DL><p>
    <DT><H3 ADD_DATE="…" LAST_MODIFIED="…" PERSONAL_TOOLBAR_FOLDER="true">Bookmarks bar</H3>
    <DL><p>
        <DT><A HREF="https://example.com/" ADD_DATE="…" ICON="data:image/png;base64,…">Example</A>
    </DL><p>
</DL><p>
```

Three details that will otherwise cost a debugging session:

1. **It is unclosed-tag SGML, not valid HTML.** There is no `</DT>`. A strict XML or DOM parser fails on it. Use a permissive tag scanner.
2. **`ADD_DATE` here is Unix epoch *seconds*** — a different base and unit from the JSON file's 1601-epoch microseconds. Two conversions, not one.
3. **The format has no GUID field.** Round-tripping through it loses stable identity; an importer must mint fresh identifiers.

`PERSONAL_TOOLBAR_FOLDER="true"` appears on exactly one folder — the bookmarks bar. `ICON` is an optional inline data URI and is safe to ignore.

### Other browsers

**Safari** — `~/Library/Safari/Bookmarks.plist`, a binary plist whose nodes carry `WebBookmarkType` (`WebBookmarkTypeList` for folders, `WebBookmarkTypeLeaf` for bookmarks), `Title`, `Children`, `URLString`, `URIDictionary`, `WebBookmarkUUID` (*recalled — Apple does not document this; validate against a real file before shipping*).

**Firefox** — `~/Library/Application Support/Firefox/Profiles/<hash>.<name>/places.sqlite`, tables `moz_bookmarks` and `moz_places`. Its timestamps are **microseconds since the Unix epoch** — a third convention; do not reuse Chrome's constant (*recalled*).

### Permission obstacles

- **Safari's `~/Library/Safari/` is TCC-protected.** Even unsandboxed, reading it fails until the user grants Full Disk Access in System Settings. Safari import needs an explicit explanation and a fallback to "export from Safari, then import the HTML file." Chrome, Brave, and Edge live in ordinary Application Support and read without a prompt (*the Chromium half is moderate confidence; smoke-test it*).
- **If Clearframe is ever sandboxed** for App Store distribution, direct path access ends. The user must choose the file through `NSOpenPanel`, and a security-scoped bookmark — not a path string — is what grants durable access.
- **Read safety.** Chrome writes `Bookmarks` by atomic rename, so reading it while Chrome runs is safe. SQLite files may be WAL-locked by a running browser; open read-only or copy the `.sqlite`/`-wal`/`-shm` set first.

### Recommended shape

Implement both readers. Native Chromium JSON gives higher fidelity and maps almost directly onto `Codable`. Netscape HTML is universal and doubles as Clearframe's own export format. Import must show a preview and never silently overwrite existing bookmarks.

## 4. Cheap wins from WebKit

Capabilities WebKit already provides that Clearframe does not yet expose. Property names verified against Apple's documentation JSON; **version floors are unreliable from that path and must be confirmed in Xcode.**

Three are a single property each:

```swift
webView.isInspectable = true                              // full Web Inspector
configuration.upgradeKnownHostsToHTTPS = true             // automatic HTTP→HTTPS
configuration.allowsPictureInPictureMediaPlayback = true  // native video PiP
```

`isInspectable` is exactly what Safari's "Show features for web developers" toggle does.

Small deltas from what already exists:

- **Per-site zoom memory.** `WKWebView.pageZoom` exists and Clearframe already uses it per session. Safari's persistence is nothing more than an origin-keyed dictionary reapplied on navigation finish.
- **Per-site media-capture memory.** `cameraCaptureState` / `microphoneCaptureState` report and revoke access. WebKit does not remember the user's grant across launches — that bookkeeping is the app's, structurally identical to zoom.
- **Download resume.** `WKDownload.cancel(_:)` hands back resumable `Data` (macOS 11.3+, verified).
- **`takeSnapshot`** for tab-hover previews.
- **`WKWebsiteDataStore(forIdentifier:)`** creates fully isolated, independently deletable data stores. This is almost certainly the mechanism behind Safari's Profiles, and it is the honest path to profiles here (*the causal link is inference*).

**Reader mode is not a WebKit API.** Confirmed by absence across `WKWebView`, `WKPreferences`, and `WKWebViewConfiguration`. Safari's Websites pane only toggles something only Safari can do. This matters strategically: Clearframe's extraction engine is not a workaround for missing plumbing — it is the only path any third-party WebKit browser has, and it is already built.

## 5. Settings architecture reference

Clearframe's Settings is one grouped form. Both mainstream browsers use a pane model worth borrowing.

**Safari** has ten panes: General, Tabs, AutoFill, Search, Security, Privacy, Websites, Profiles, Extensions, Advanced (*verified*). Passwords is **not** a pane — it moved to the system Passwords app.

The pane worth copying is **Websites**, a per-site permission matrix covering Reader, Content Blockers, Auto-Play, Page Zoom, Camera, Microphone, Screen Sharing, Location, Downloads, Notifications, Pop-up Windows, and Lockdown Mode. Each category splits sites into "Currently Open" and "Configured", and each ends with a "When visiting other websites" default.

Clearframe is already partway there — per-site tracker-blocking exceptions and per-site data removal are the same shape, without the frame around them.

**Chrome** organizes as People · Autofill and passwords · Privacy and security · Performance · **AI** · Appearance · Search engine · Default browser · On startup · Languages · Downloads · Accessibility · System · Reset settings (*verified from `settings_menu.html`*). Its per-site permission enum runs to roughly fifty entries — most are device APIs (USB, HID, Serial, MIDI, Bluetooth) that WebKit does not expose and Clearframe will never need.

Note the **AI** section: Google now ships a first-party AI settings surface in Chrome. They are building toward the same sentence Clearframe uses — making AI simple. Differentiation cannot be *having* AI.

## 6. Competitive read

**Brave** — privacy by default, plus a crypto wallet, a rewards token, and its own ad network. The privacy defaults are the model; the economics are explicitly rejected here.

**Opera** — the browser as an app hub: embedded messengers, workspaces, tab islands, a bundled VPN. Scope creep as a strategy.

**Vivaldi** — maximal customization for power users: tab stacking and tiling, web panels, a command palette, gesture systems, keyboard remapping, and a built-in mail, calendar, and feed reader. The wrong audience for ordinary users, and an enormous support surface for a small team.

**Arc, and the lesson.** The Browser Company built the most admired reimagined browser of the era — vertical tabs, Spaces, split view, auto-archiving — reached roughly a million users, and **stopped feature development in May 2025**, keeping only security fixes. The stated reason was that Arc had become too complex for mainstream users; they called it a novelty tax. They pivoted to Dia, an AI browser, and **Atlassian acquired the company for $610M in September 2025** (*acquisition verified; the complexity reasoning is widely reported rather than confirmed here*).

Two conclusions, and they pull in opposite directions. People **will** switch browsers for something better — a million did. And the team that executed the reimagined browser best of all abandoned it because it asked users to learn too much. `clearframe-strategy.md` already says clarity outranks feature count; Arc is the case study.

The practical test for any new feature: **does it need explaining?** "Your bookmarks come with you" needs none. A new organizational concept sitting beside the tab groups that already exist needs a paragraph, and that is the warning sign.

**Where the funded players are going.** Agentic AI — Atlas, Dia, Gemini in Chrome, Comet. That race cannot be won by a solo founder, on model quality, infrastructure, or the safety engineering an agent that clicks buttons genuinely requires. But none of them will build a browser that understands pages *without sending them anywhere*, because their value is the model. That gap is available because it is uninteresting to them, not because nobody noticed it.

**Worth adopting, ranked by value over cost:** split view (every challenger reinvented it independently, which is real evidence of demand) · a tab and command palette (Spotlight is a pattern users already know) · a visible tab-sleep affordance (WebKit already suspends background tabs; the work is mostly telling the user) · vertical tabs, opt-in only.

**Not worth adopting:** gesture and keyboard-remapping systems · built-in messengers, mail, or feeds · a bundled VPN (it would make Clearframe the intermediary for user traffic, against everything else it promises) · crypto anything · agentic page actions · named session save/restore, which overlaps what tab groups and restore already do.

## 7. Ideas that compound on what already exists

Clearframe's engine extracts reading blocks, scores sentences, detects claims, maps a sentence back to the live DOM, and classifies page structure. Nothing else in this document is unavailable to a competitor with money; this is.

All of the following are local-only, need no server and no new model, and take no action on the user's behalf.

1. **Evidence Sheet** *(low cost)* — a printable view listing each key point and claim beside its exact quoted sentence. Reuses extraction and the existing print support. A citation sheet a person can hand to someone else. Cheapest item here and the most immediately demonstrable.
2. **Find what answers this** *(moderate)* — rank reading blocks by relevance to a typed question using the existing sentence scorer, then jump and highlight through the existing DOM mapping. Better than ⌘F on long pages, and it points at the real sentence rather than generating a paragraph about it.
3. **Structural outline** *(moderate)* — surface the structure classification already computed as a clickable outline that jumps into the page through the same anchors Evidence Mode uses.
4. **Cross-tab claim comparison** *(high cost, highest ceiling)* — when several open tabs cover one subject, compare their extracted claims locally and surface disagreement calmly: "three open tabs state a different price." No mainstream browser reconciles facts across pages; the AI browsers summarize one page or act on it. Must read as "these disagree", never as a verdict — the same rule that governs risk signals.
5. **Claim watch** *(high cost)* — bookmark a specific claim rather than a page; on revisit, re-extract and report if that sentence changed or vanished. Nobody does this. A longer-term bet.

## 8. What was not verified

Named so nobody treats this file as more certain than it is.

- Safari's Search pane control labels, its Extensions per-site permission wording, and whether a Privacy Report surface still exists.
- Whether Chrome blocks third-party cookies by default as of August 2026 — the timeline moved repeatedly through 2024–2025.
- Every WebKit API version floor quoted in section 4.
- Safari's `Bookmarks.plist` field names and Firefox's `places.sqlite` schema.
- Opera's agentic "Neon" product, and Zen's workspace and compact-mode details.
- Whether Chromium's Application Support folders are free of TCC gating — relied on by existing importer tools, but worth a smoke test.

## Related

[clearframe-strategy.md](clearframe-strategy.md) · [project-context.md](project-context.md) · [market-research.md](market-research.md) · [macos-browser-foundation.md](macos-browser-foundation.md) · [content-blocking.md](content-blocking.md) · [go-to-market.md](go-to-market.md)
