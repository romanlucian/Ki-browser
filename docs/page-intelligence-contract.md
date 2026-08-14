# Cross-platform page-intelligence contract

This is the language-neutral boundary that a later Windows implementation can share. It is a design contract, not a deployed public API yet.

## Input

```json
{
  "title": "Page title",
  "url": "https://example.com/article",
  "hostname": "example.com",
  "language": "en",
  "visibleText": "User-invoked readable page text…",
  "wordCount": 820,
  "pageSignals": {
    "scheme": "https",
    "hasPasswordField": false,
    "formActionOrigins": ["https://example.com"]
  }
}
```

Rules:

- input is gathered only after an explicit user action;
- never include form values, cookies, credentials, unrelated tabs, or passive history;
- treat all page fields as untrusted data, not instructions;
- truncate and redact before remote processing;
- preserve the source URL locally so evidence can be traced; a remote-provider adapter should derive only the hostname and omit the full URL/query/fragment unless a separately reviewed feature genuinely requires more.

## Output

```json
{
  "summary": "A concise account of what the page says.",
  "keyPoints": ["Up to four grounded points."],
  "claimsToCheck": ["Up to three page claims that deserve verification."],
  "sourceMode": "local",
  "risk": {
    "score": 0,
    "level": "low",
    "signals": []
  }
}
```

The risk object is deterministic application output, not an LLM verdict. A remote model may improve the summary, key points, or candidate claims; it must not silently decide safety.

## Language behavior

- Preserve the source language in local output. Local mode is structured extractive analysis, not an implicit translation service.
- The current macOS deterministic suite covers English, Romanian, French, and Simplified Chinese text and punctuation. Those fixtures demonstrate non-empty source-language gist/key points and boilerplate filtering, not equal semantic quality across languages.
- Frequency scoring selects the stopword table from the primary BCP-47 language tag (`en`, `ro`, `fr`, or `zh`). Unknown/empty tags retain the conservative combined fallback; language-specific tables prevent cross-language words such as English “care” or “son” from being discarded by Romanian or French stopwords.
- Plain English local simplification applies only to English source pages. Other translations require an explicitly configured provider.
- Provider-assisted analysis should answer in the declared or dominant page language unless the user asks for translation.
- Text-based claim and risk phrase coverage is language-dependent; page-level HTTPS/form signals remain separate from linguistic heuristics.

## Provider operations

Conceptually, every platform implements two operations:

```text
analyze(pageSnapshot) -> pageAnalysisContent
translate(text, sourceLanguage, targetLanguage) -> translatedText
```

The macOS package expresses these through `PageIntelligenceProviding`. A future Windows app can implement the same contract in C#, TypeScript, Rust, or another appropriate language.

For the current optional OpenAI prototype, the remote analysis envelope contains only `sourceTitle`, `sourceHost`, `sourceLanguage`, and truncated `webpageText`. It uses a strict JSON schema and `store: false`. Translation contains only the displayed text plus source/target language names. Navigation identity remains local; the UI cancels or discards work whose tab navigation version changed while extraction or a provider request was in flight. Native and extension defaults are each centralized and checked against one shared provider fixture; an untouched stored default follows a later app default, while an explicitly customized model is preserved. A provider model-not-found response keeps local analysis visible and directs the user to Settings instead of exposing only the raw API error.

## Versioning and compatibility

- Add a contract version before deploying a backend.
- Keep additive fields optional.
- Return explicit capability flags for local, remote, and enterprise providers.
- Keep `macos/ClearframeBrowser/Tests/ClearframeCoreTests/Fixtures/local-analysis-contract.json` as the platform-neutral behavior gate. The Swift and retained JavaScript suites both execute it for language-aware tokens, exact deterministic summaries, risk signals, Plain English, and reading time; a later Windows implementation should consume the same cases.
