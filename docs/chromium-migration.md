# Chromium migration foundation

**Decision date:** August 10, 2026
**Status:** Architecture selected and isolated validation scaffold added. No Chromium renderer has been integrated into the installed app.

## The decision

Clearframe should evaluate **Chromium Embedded Framework (CEF)** as the rendering foundation for a future macOS build. The current `dist/Clearframe.app` and installed `/Applications/Clearframe.app` remain the tested SwiftUI + WebKit version-1 baseline.

CEF is the official open-source embedding layer built on Chromium/Blink. It provides stable C/C++ APIs, release branches that track Chromium, binary distributions, a multi-process renderer, and macOS sample applications. Clearframe can keep its native SwiftUI chrome and reusable `ClearframeCore` while a small Objective-C++ layer owns CEF objects and exposes an Objective-C interface to Swift.

This is a Chromium-based application architecture, but it is **not Google Chrome** and is **not yet a working Clearframe Chromium browser**. DuckDuckGo is only the current app's changeable initial search provider; it is not the current rendering engine.

## Why CEF

CEF fits the requested product and existing code better than the main alternatives:

- **CEF:** embeds Chromium inside a native application, supports macOS ARM64 binary distributions, and lets Clearframe retain SwiftUI and the local analysis/service layer. This is the selected path.
- **Electron:** is a complete Chromium + Node application runtime rather than a native Swift embedding layer. Adopting it would replace most of the macOS UI architecture, and Electron's own security guidance requires especially careful isolation for arbitrary remote content.
- **A full Chromium fork:** offers maximum browser control but creates a much larger source build, patch, security-update, branding, and release-engineering burden. It is not justified for the next validation stage.
- **Community Swift wrappers:** CEF explicitly maintains its base C/C++ API, not external language wrappers. A small Clearframe-owned Objective-C++ boundary is easier to audit and keep current than making a third-party wrapper a core dependency.

## Intended architecture

```text
SwiftUI browser window and product UI
              |
              v
ClearframeChromiumBridge (Objective-C API, Objective-C++ implementation)
              |
              v
CEF C++ browser/client handlers + Chromium helper processes

ClearframeCore remains alongside this path for local analysis, risk signals,
source comparison, provider contracts, and persistent data models.
```

The bridge should expose a narrow, asynchronous interface for navigation state, title/URL updates, loading and failure state, popup policy, downloads, permissions, and explicit visible-page extraction. CEF reference-counted objects and C++ callbacks must not leak into Swift.

Each Clearframe tab will own one `CefBrowser` lifecycle. Closing a tab must detach callbacks and close its browser host. Profiles, cookies, and cache should use a deliberate local request-context policy rather than CEF defaults chosen accidentally.

Page extraction remains local-first and user-triggered. On **Analyze page**, the browser process may ask the renderer for sanitized visible text through CEF's asynchronous message-router/IPC pattern. Opening a page must never trigger provider upload.

## Dependency and build implications

The isolated scaffold lives at `chromium/cef-spike`. It does not participate in the existing Swift Package or app-bundle script.

The initial target is the current Apple Silicon host:

- macOS ARM64;
- CEF `151.3.16+gbe1e15d+chromium-151.0.7922.109`, stable binary published August 8, 2026;
- the publisher's minimal archive is about 131 MB compressed before Clearframe code, symbols, or final app packaging;
- CMake 3.21 or newer and Xcode are required by the official `cef-project` CMake path;
- the official sample currently documents Python 3.9 through 3.11 for its setup/download tooling;
- the official sample currently documents tested Xcode versions 13.5 through 16.4 on macOS 12 or newer. This host has Xcode 26.6, so compatibility must be proved rather than assumed.

The version and publisher-provided SHA-1 metadata are recorded in `chromium/cef-spike/cmake/CEFVersion.cmake`. Before a dependency is accepted into CI, download it from the official automated builder, verify the published checksum, calculate and pin a SHA-256 checksum in project-controlled dependency metadata, and retain the exact archive in a controlled build cache. The scaffold intentionally does not download a 131 MB runtime during normal configuration.

Swift Package Manager is still suitable for `ClearframeCore`, but it is not sufficient by itself for CEF's native build and bundle topology. The CEF target should be generated with CMake/Xcode and must package:

- `Chromium Embedded Framework.framework` and its resources;
- the required Clearframe Helper app/executable for renderer, GPU, and other subprocess roles;
- appropriate `Info.plist` files, identifiers, sandbox/hardened-runtime configuration, and signatures for every nested executable;
- architecture-specific output. Intel support should be built and tested from the matching `macosx64` CEF distribution rather than assumed from the ARM64 build.

The official `cefsimple` target is the correct first executable reference. Clearframe should adapt its lifecycle and bundle layout, not write a custom CEF bootstrap from memory.

## Feature parity and product risks

The current `WKWebView` cannot be mechanically replaced. The reusable data and intelligence layers survive, but browser integration must be reimplemented and regression-tested.

| Area | Reuse | Chromium migration work |
| --- | --- | --- |
| SwiftUI toolbar, tab strip, assistant UI | Mostly reusable | Host a native CEF view and revalidate focus/accessibility |
| URL/search resolution | Reusable | Preserve the explicit local choice among DuckDuckGo, Google, Bing, Brave Search, and Startpage |
| Bookmarks, history, session records | Models and local store reusable | Feed navigation/title events from CEF and validate restored URLs |
| Tabs | Workspace model reusable | One CEF browser per tab; asynchronous close and crash lifecycle |
| Downloads | Product UI reusable in concept | Implement CEF download callbacks, destination confirmation, cancellation, and quarantine expectations |
| Loading/error/offline state | UI reusable in concept | Map CEF load-error, certificate, auth, crash, and network callbacks |
| Page assistant | `ClearframeCore` reusable | New renderer IPC/JavaScript extraction path, only after explicit action |
| Voice and Keychain settings | Largely engine-independent | Retest focus and permission presentation |
| WebKit smoke harness | Not reusable as engine coverage | Add CEF local-fixture and helper-process tests |

Important non-parity risks:

- CEF provides Chromium/Blink, not Chrome branding, Google account sync, Chrome Safe Browsing services, Google APIs, password sync, or automatic Chrome Web Store compatibility.
- DRM/Widevine, proprietary codecs, media capture, screen sharing, notifications, geolocation, client certificates, HTTP authentication, and site permissions require explicit product and licensing decisions.
- Chromium's rapid security cadence becomes Clearframe's operational responsibility. A browser release cannot remain on an old CEF build after relevant Chromium security fixes.
- The multi-process app is materially larger and more complicated to package, sign, notarize, update, and crash-diagnose than the current WebKit bundle.
- CEF callbacks cross processes and threads. Unsafe ownership, blocking work, or a poorly designed bridge can introduce crashes and privacy defects.
- Supporting arbitrary web content requires hardened popup, navigation, download, permission, protocol, certificate, DevTools, and renderer-crash policies before public release.

## Licensing and distribution

CEF uses a BSD-style license and includes Chromium plus many third-party components. A distributed app must include the CEF license and the applicable Chromium/third-party notices from the exact binary distribution. `about:license` and `about:credits` are useful references but do not replace a maintained in-app/legal notices surface.

Clearframe must not use Google Chrome names, icons, trademarks, proprietary services, or imply a Google partnership. Codec, DRM, patent, export, privacy, and app-distribution questions need release-specific legal review. This document is engineering guidance, not legal advice.

Every helper and framework in the final `.app` must be signed consistently before notarization. The present ad hoc-signed WebKit bundle does not validate the future CEF signing layout. A public Chromium build also needs a tested updater capable of shipping urgent browser-engine updates safely.

## Incremental implementation plan

1. **Freeze the working baseline.** Keep WebKit Clearframe buildable, testable, and installable. Record parity fixtures and do not change the default app renderer.
2. **Prove official CEF on this toolchain.** Install CMake, fetch the pinned official ARM64 minimal distribution, verify checksums, build and run official `cefsimple`, and record whether Xcode 26.6 needs patches or an older supported Xcode toolchain.
3. **Build the native bridge spike.** Implement one local-fixture CEF view in a separate target. Prove startup/shutdown, address focus, navigation callbacks, back/forward/reload, renderer crash recovery, and helper-process packaging.
4. **Prove one Clearframe tab.** Connect the existing SwiftUI toolbar to the bridge, but keep a distinct experimental bundle identifier and output path. Test local pages before live sites.
5. **Reach browsing parity.** Port safe tab lifecycle, session restoration, bookmarks/history, downloads, popups, errors, permissions, authentication, certificate presentation, and profile/data deletion.
6. **Reach assistant parity.** Add explicit visible-page extraction over asynchronous renderer IPC, then local analysis and optional provider use. Verify no extraction or upload occurs on ordinary navigation.
7. **Security and distribution gate.** Add CEF update monitoring, hostile-page tests, sandbox/signing/notarization work, accessibility QA, privacy review, third-party notices, crash/update infrastructure, and independent security review.
8. **Cut over only after evidence.** Replace the WebKit default only when the Chromium build passes the agreed parity, privacy, security-update, and packaging gates. Until then, the installed app remains WebKit.

## Current scaffold validation status

The repository now contains:

- a pinned CEF dependency descriptor;
- a configure-only CMake gate that can validate a local CEF binary distribution and build `libcef_dll_wrapper` when enabled;
- a Swift-facing Objective-C bridge contract with no runtime implementation;
- a host-readiness script that performs no downloads or installations.

The current host has Apple Silicon, macOS 26.5, Xcode 26.6, Swift 6.3.3, and Python 3.14.6. CMake is not installed, and Python 3.14 is outside the official sample project's documented 3.9–3.11 range, so a real CEF configure/build was not attempted. Those are toolchain prerequisites, not failures of the existing Clearframe app. Installing CMake, selecting a compatible Python environment, and downloading the pinned runtime are explicit next-phase actions because they change the machine and fetch a large dependency.

## Primary sources

- [CEF project and BSD license](https://github.com/chromiumembedded/cef)
- [Official CEF sample project and build requirements](https://github.com/chromiumembedded/cef-project)
- [CEF architecture, binary distributions, macOS bundle layout, processes, and licensing](https://chromiumembedded.github.io/cef/general_usage)
- [Official CEF tutorial](https://chromiumembedded.github.io/cef/tutorial)
- [Automated CEF binary distributions](https://cef-builds.spotifycdn.com/index.html)
- [Electron security guidance](https://www.electronjs.org/docs/latest/tutorial/security)
