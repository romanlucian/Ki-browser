# Clearframe repository guidance

Use [AGENTS.md](AGENTS.md) as the authoritative development instruction file and read [docs/project-context.md](docs/project-context.md) before proposing or implementing product-direction changes.

Essential constraints:

- The current installed product is a standalone, macOS-first SwiftUI + WebKit browser for ordinary users.
- The future Chromium path is an isolated CEF migration scaffold; it is not linked into the current app and is not a full Chromium source fork.
- The root browser extension is a retained validation artifact, not the primary deliverable.
- Page assistance is local-first; optional provider use happens only after an explicit user action.
- Never sell browsing history, add hidden ads, invent partnerships, or market heuristic risk signals as security verdicts.
- Preserve the `ClearframeCore` versus macOS UI/WebKit boundary and document material behavior or data-flow changes.
- Do not claim production signing, notarization, App Store readiness, password security, or security review without evidence.

The root [README](README.md#documentation-index) links the product, architecture, privacy, research, run, and release-gap documents.
