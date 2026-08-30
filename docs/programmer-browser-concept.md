# Side concept: Clearframe for programmers

**Status:** future product direction only. This does not change the current general-audience macOS browser build and is not a second browser project now.

## Target users

Software developers, technical founders, support engineers, and students who spend substantial time moving between documentation, GitHub, issue trackers, technical articles, and an editor such as VS Code.

## Problems it could solve

- Documentation is fragmented across versions, vendors, examples, and outdated search results.
- GitHub repositories are hard to understand before cloning: architecture, active areas, issues, releases, and setup are scattered.
- Code snippets on the web often omit dependencies, version assumptions, security limits, and surrounding context.
- Research disappears across tabs instead of becoming a reusable technical decision record.
- Copying context manually between the browser and editor is slow and error-prone.

## Focused promise

> Turn technical browsing into a source-linked research brief that can move cleanly into the developer’s existing editor.

The promise is comprehension and handoff, not autonomous coding in the browser.

## First features

**Note, August 30, 2026.** Every lens below assumes a reader that can summarize and extract meaning. Clearframe no longer has one — page judgment was removed, and the browser now prepares text rather than interpreting it. This concept therefore depends on a model arriving first.

1. **Documentation lens:** identify product/version, summarize the current page, extract prerequisites, and flag likely version mismatches.
2. **GitHub lens:** explain repository purpose and structure from visible pages, summarize releases/issues, and keep links to original evidence.
3. **Code explanation:** explain selected snippets, inputs/outputs, dependencies, and risks without pretending the snippet is verified or complete.
4. **Research workspace:** collect pages, snippets, claims, and citations into a Markdown technical brief with an explicit “open questions” section.
5. **Source comparison:** compare two docs or approaches by version, API shape, constraints, and evidence rather than generic prose similarity.

## VS Code connection, not replacement

The browser should hand off useful artifacts to VS Code instead of rebuilding an IDE:

- export or copy a Markdown research brief;
- send selected code and source URLs into a new scratch file;
- open a repository or local workspace through an explicit user action;
- expose a small local protocol/extension so VS Code can request the current research set;
- receive filenames or symbols from VS Code only with narrow, visible permission.

It should not implement editing, terminals, debugging, Git operations, or hidden workspace indexing. Those jobs already belong to VS Code and other editors.

## Monetization

- **Free:** local page explanation, limited research sets, Markdown export.
- **Developer Pro:** higher AI limits, larger cross-source workspaces, version-aware comparison, team-ready exports.
- **Team/Business:** shared research sets, approved model routing, retention policy, admin controls, and private documentation connectors.
- **Potential referrals:** clearly labeled developer-tool recommendations only after explicit intent; never bias code explanations or security warnings.

## Why this remains future expansion

The general-audience browser still needs to prove its core behavior: users repeatedly ask it to understand pages, compare sources, and return. Programmer workflows add GitHub semantics, editor integration, code-security expectations, version resolution, and a different acquisition channel. Building both now would split product learning and create two incomplete positioning stories.

Revisit this direction only after the shared page-intelligence core is stable and interviews show a concentrated developer segment with materially higher retention or willingness to pay. If validated, it should be a mode or packaged workflow on the same browser foundation—not a second browser codebase.
