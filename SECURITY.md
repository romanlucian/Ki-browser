# Clearframe security policy

Clearframe is an early macOS/WebKit browser foundation, not a production-security-reviewed consumer release. The current `main` branch is the only version receiving fixes; no tagged public release is supported yet.

## Reporting a vulnerability

Use the repository's **Security → Report a vulnerability** flow to open a private GitHub security advisory. Include the affected commit, reproducible steps, impact, and the smallest safe proof of concept. Do not place secrets, private browsing data, or an active exploit in a public issue.

If private reporting is unavailable, open a public issue that asks the maintainer to enable a private channel, without disclosing exploit details.

## Current boundaries

- Page content is untrusted and the assistant is read-only.
- Local page extraction occurs only after an explicit Analyze Page action.
- Optional provider requests are explicit and use a user-owned prototype key.
- Risk indicators are explainable heuristics, not malware or safety verdicts.
- The local app bundle is not a claim of Developer ID signing, notarization, independent review, download scanning, or password-manager security.

Please also read [docs/privacy-and-safety.md](docs/privacy-and-safety.md) and [docs/macos-browser-foundation.md](docs/macos-browser-foundation.md).
