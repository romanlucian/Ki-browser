# Tracker blocking

**Current list:** `2026.08.14.1`, manually checked August 14, 2026.

Limeghost can block network requests to a small, first-party curated list of common advertising and tracking domains. It ships as Swift-embedded data in `LimeghostCore` (`macos/LimeghostBrowser/Sources/LimeghostCore/TrackerBlockerCatalog.swift` and `TrackerBlockerCatalogData.swift`), compiles into the app, and changes only through a reviewed app update. There is no remote fetch, analytics feed, or automatic list update in this phase.

## What it blocks

- Third-party network requests whose destination host matches an entry on the bundled list — the domain itself or any subdomain of it.
- Only the resource types a tracking domain typically uses: script, image, style-sheet, font, media, raw (background requests such as XHR/fetch), popup, and document. `document` covers third-party iframes; navigating directly to a listed domain stays first-party and keeps working.
- Blocking is third-party only by default: a request the visited site makes to its own domain is never blocked by this feature, only requests aimed at a domain on the list.
- Enforcement happens inside WebKit's content-rule-list engine, in the page's own process — the same mechanism Safari content blockers use.

## What it does NOT block

- First-party analytics a site runs from its own domain or a domain it visibly owns.
- Cookie-based tracking. Limeghost does not manage, partition, or strip cookies as part of this feature.
- Browser fingerprinting (canvas, font, or timing-based identification techniques).
- CNAME-cloaked trackers, where a site proxies a tracker through a subdomain of its own domain. The bundled list matches literal tracker domains, not disguised first-party-looking hostnames.
- A per-page or running count of blocked requests. WebKit applies the compiled rules inside the page process and never reports back which rules fired, so Limeghost genuinely cannot see or count what was blocked. The UI never shows a number — see "Honest UI rule" below.

## Inclusion and exclusion criteria

The list is a starting point, not an exhaustive replacement for a dedicated ad blocker. A domain is included only when its primary third-party function is ad delivery or audience measurement: ad exchanges, ad servers, tracking pixels/beacons, session-replay scripts, and native-ad widgets. The list deliberately excludes:

- Tag managers (for example `googletagmanager.com`), because blocking them can break unrelated site functionality that has nothing to do with tracking.
- Consent-management platforms, because blocking them can trap a site behind a broken cookie banner.
- Login and social SDKs (for example `connect.facebook.net`), because blocking them can break sign-in flows a person is trying to use.
- General-purpose CDNs, because they host far more than tracking code.

Domains are lowercase, deduplicated, and sorted before they ship.

## First-party provenance

Every entry is a first-party editorial decision, the same review model as the [AI catalog](ai-catalog-editorial.md). The list is not imported from EasyList, uBlock filter lists, or any other third-party blocklist project. Importing a third-party list is future work that first needs a licensing and attribution review — several popular lists carry their own conditions on redistribution and modification. Until that review happens, the bundled list stays small and hand-curated.

## Manual update workflow

Mirrors the [AI catalog editorial workflow](ai-catalog-editorial.md#manual-weekly-review-workflow), adapted for a domain list instead of a tool catalog:

1. Re-check that each domain still resolves and still functions as an ad/tracking endpoint; drop entries that have gone dark or changed purpose.
2. Apply the inclusion/exclusion criteria above to any candidate addition; when in doubt, leave a domain out rather than risk breaking ordinary site functionality.
3. Keep the list lowercase, deduplicated, and sorted.
4. Update the version string and checked date at the top of this document together with `TrackerBlockerCatalog.release`.
5. Run `swift test` — the catalog-hygiene and generator tests enforce shape, dedup, sort order, and that every action stays `block` — plus the native smoke test where the macOS host permits it.
6. Commit the catalog data, tests, and this document together so the Git history explains the change.

No third party can buy a listing or removal.

## Exceptions: how the per-site off switch works

A person can turn blocking off for the current site from the shield button in the address bar, or manage every exception from Settings → Tracker blocking.

- Exceptions are stored as normalized hostnames (lowercase, `www.` stripped) in local `UserDefaults` — nothing is sent anywhere.
- An exception for `example.com` also covers `www.example.com`, because both normalize to the same stored host. It does **not** cover other subdomains such as `shop.example.com` or `mail.example.com`; each one needs its own exception if it should be excluded too.
- Exceptions apply in private tabs too, since tracker blocking is a web-view setting rather than a history or cookie feature.
- "Clear local browsing data" in Settings clears every stored exception along with the rest of local browsing data.
- Turning tracker blocking off entirely (the global Settings switch) deletes Limeghost's compiled rule-list artifacts from disk, because a compiled list encodes exactly which sites it was excluded from and none of that should linger once blocking is off. Turning blocking back on pays for one fresh compile — a deliberate privacy/cleanliness trade-off, not a bug.

## Compile caching and the launch-window caveat

Compiling the rule list is not free, so Limeghost reuses a previously compiled list whenever the configuration has not changed. The compiled list's identifier folds in the shipped list version and a hash of the current sorted exception set, so `lookUpContentRuleList` can find an existing match before paying for a recompile; stale `limeghost-tracker-block.*` identifiers from an earlier version or exception set are cleaned up once a new one is confirmed.

One honest caveat: a tab that is already loading a page when the very first compile completes is not retroactively protected. The rules attach to that web view, but requests the page already issued are not replayed against them. The next navigation or reload in that tab is covered normally. This only matters in the brief window around app launch, before the shipped list finishes its first compile.

## Honest UI rule

Every surface that mentions tracker blocking — the address-bar shield and Settings — states only what is currently true (on for this site, not blocking yet, off for this site, off in Settings, or the filter could not be loaded) and never renders a count of blocked requests. WebKit does not report that number back to the app, so Limeghost cannot know it, and the UI does not imply otherwise.

“Not blocking yet” is the launch-window caveat above, said out loud. While the first compile is in flight no rule list is attached to any web view, so the shield must not read “On for this site”: it is neutral, it says nothing is being blocked yet, and its popover explains that the filter applies to pages opened once it is ready and that reloading covers the current page too.
