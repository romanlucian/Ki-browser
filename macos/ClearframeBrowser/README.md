# ClearframeBrowser for macOS

Native SwiftUI + WebKit standalone browser foundation for Clearframe.

This release stage provides a three-step first-run introduction, multi-tab browsing, a native new-tab AI guide, local tab restoration, user-confirmed downloads, local bookmarks/history, robust loading and error states, an address-bar and Settings chooser for five search providers, explicit on-device dictation into the address field, and the user-triggered local-first page assistant.

The introduction stores only a local completion flag, reuses the existing local search selection, and can be reopened from Settings without clearing browser data. It includes no account, tracking, purchase flow, or paywall.

DuckDuckGo is the initial search default, not the browser engine. Click its name inside the address bar—or use Clearframe Settings—to choose Google, Bing, Brave Search, or Startpage instead. The choice stays in local preferences, and no provider partnership is claimed.

The AI guide is a static catalog stored in the app. Its search and task filters run locally, and cards open direct official HTTPS destinations. Clearframe claims no listing partnership or live ranking, adds no affiliate/tracking parameters, and does not attach the current page or a prompt.

## Build the Finder app

```bash
./scripts/build-macos-app.sh
```

Then open `../../dist/Clearframe.app` from Finder. The bundle is for local development only: it has an ad hoc local signature, not a Developer ID signature or notarization ticket.

## Develop and test

```bash
swift test
swift run ClearframeBrowser
./scripts/run-browser-smoke.sh
```

`swift run` is a developer-only workflow. The packaged `.app` is the intended user launch path and explicitly activates its native window and focuses the address field.

The app requires macOS 14+ and a recent Xcode/Swift toolchain.

`ClearframeCore` contains platform-independent analysis concepts and the remote-provider protocol. `ClearframeBrowser` contains the macOS-only SwiftUI, WebKit, and Keychain implementation.

See [the architecture and limits](../../docs/macos-browser-foundation.md) before treating this as a consumer browser. It is a practical version-1 MVP, not yet a signed, notarized, security-reviewed replacement for Safari or Chrome.
