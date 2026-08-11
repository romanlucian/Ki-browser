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
- preserve the source URL so evidence can be traced.

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

## Provider operations

Conceptually, every platform implements two operations:

```text
analyze(pageSnapshot) -> pageAnalysisContent
translate(text, sourceLanguage, targetLanguage) -> translatedText
```

The macOS package expresses these through `PageIntelligenceProviding`. A future Windows app can implement the same contract in C#, TypeScript, Rust, or another appropriate language.

## Versioning and compatibility

- Add a contract version before deploying a backend.
- Keep additive fields optional.
- Return explicit capability flags for local, remote, and enterprise providers.
- Test the same fixtures on macOS and Windows so summaries, risk rules, and comparison semantics do not drift silently.
