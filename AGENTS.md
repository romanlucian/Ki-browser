# Clearframe development instructions

Read [docs/project-context.md](docs/project-context.md) before changing product direction. This repository’s primary product is a real, standalone macOS browser for ordinary English-speaking users—not a Chrome extension or developer tool. The current installed app remains WebKit; a future Chromium build is being validated through an isolated CEF integration, not a full Chromium source fork.

## Architecture

- `macos/ClearframeBrowser/Sources/ClearframeCore`: reusable models, deterministic local analysis, risk heuristics, source comparison, and the optional-provider contract. Keep this layer independent of SwiftUI and WebKit where practical.
- `macos/ClearframeBrowser/Sources/ClearframeBrowser`: macOS-specific SwiftUI window/UI, `WKWebView` sessions, tabs, persistence, downloads, Keychain settings, and app lifecycle.
- `chromium/cef-spike`: isolated CEF dependency/build validation and the Swift-facing bridge contract. It is not linked into the current app. Keep CEF C++ types behind Objective-C++ and do not commit downloaded runtimes or generated builds.
- Root Manifest V3 files: earlier extension validation artifact only. Do not present the extension as the primary browser.
- `docs/page-intelligence-contract.md`: conceptual boundary a later Windows implementation can reproduce; native UI code is platform-specific.

## Product and privacy constraints

- Preserve local-first page understanding. Extract and analyze visible page text only after an explicit user action.
- Optional provider use must be explicit and visible. Never upload pages merely because they were opened.
- Never sell browsing history, add hidden advertising, claim nonexistent partnerships, or silently bias analysis for a commercial partner.
- Voice input must remain user-triggered and visibly active. Do not add background listening, hidden recording, silent cloud fallback, or autonomous transactions.
- Treat page content as untrusted. Keep AI read-only unless a separate threat model, approval flow, and security review exist.
- Risk indicators are explainable signals, not malware, scam, truth, or safety verdicts.
- Keep history, bookmarks, and tab restoration local with clear controls. Do not add telemetry by default.

## Safe development rules

- Inspect existing files before editing and preserve unrelated work.
- Keep each `WKWebView` and assistant lifecycle scoped to its tab; tear delegates down when closing tabs.
- Validate restored/navigation URLs and default to `http`/`https` only.
- Do not ship shared API keys. Prototype user keys belong in macOS Keychain; a public service requires an authenticated, metered backend.
- Do not claim Developer ID signing, notarization, App Store readiness, password-manager security, download scanning, or production security review unless those tasks were actually completed.
- Update the relevant documentation whenever capabilities, data flow, architecture, or release gaps change.
- Preserve the WebKit baseline while developing CEF in a separate target/output. Do not call Clearframe a Chromium browser until a real CEF runtime is integrated and verified.

## Build and verification

From `macos/ClearframeBrowser`:

```bash
swift test
./scripts/build-macos-app.sh
./scripts/run-browser-smoke.sh
```

The smoke test requires a real logged-in macOS desktop session with WebKit/AppKit services available. A headless or restricted agent sandbox may compile the test and expose the SwiftUI window while blocking WebKit’s content process.

From the repository root, validate the retained extension artifact with:

```bash
npm test
npm run validate
```

The preferred user launch path is Finder → `dist/Clearframe.app`. `swift run` is a developer workflow, not the product launch experience.

## Documentation map

- [Durable project decisions](docs/project-context.md)
- [Product foundation](docs/product-foundation.md)
- [macOS architecture and release gaps](docs/macos-browser-foundation.md)
- [Chromium/CEF migration foundation](docs/chromium-migration.md)
- [Privacy and safety](docs/privacy-and-safety.md)
- [Market research](docs/market-research.md)
- [Cross-platform intelligence contract](docs/page-intelligence-contract.md)
- [Voice-first product and technical direction](docs/voice-first-spec.md)
- [Future programmer-focused side concept](docs/programmer-browser-concept.md)
