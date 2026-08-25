import test from "node:test";
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import {
  assessRisk,
  assessStructure,
  simplifyEnglish,
  summarizeLocally,
  tokenize
} from "../src/core/analyzer.js";

const contractURL = new URL(
  "../macos/ClearframeBrowser/Tests/ClearframeCoreTests/Fixtures/local-analysis-contract.json",
  import.meta.url
);
const contract = JSON.parse(await readFile(contractURL, "utf8"));

function extensionPage(page) {
  return {
    ...page,
    liveUrl: page.url,
    protocol: `${page.scheme}:`
  };
}

test("shared contract: language-aware tokenization", () => {
  for (const testCase of contract.tokenCases) {
    const tokens = tokenize(testCase.text, testCase.language);
    for (const [token, expectedCount] of Object.entries(testCase.requiredCounts)) {
      assert.equal(
        tokens.filter((candidate) => candidate === token).length,
        expectedCount,
        `${testCase.id}: ${token}`
      );
    }
    for (const excluded of testCase.excluded) {
      assert.ok(!tokens.includes(excluded), `${testCase.id}: retained ${excluded}`);
    }
  }
});

test("shared contract: deterministic local summaries", () => {
  for (const testCase of contract.summaryCases) {
    assert.deepEqual(summarizeLocally(extensionPage(testCase.page)), testCase.expected, testCase.id);
  }
});

test("shared contract: page structure assessment", () => {
  for (const testCase of contract.structureCases) {
    assert.equal(assessStructure(extensionPage(testCase.page)), testCase.expected, testCase.id);
  }
});

test("shared contract: risk signals", () => {
  for (const testCase of contract.riskCases) {
    const risk = assessRisk(extensionPage(testCase.page));
    assert.equal(risk.score, testCase.expected.score, `${testCase.id}: score`);
    assert.equal(risk.level, testCase.expected.level, `${testCase.id}: level`);
    assert.deepEqual(risk.signals.map((signal) => signal.title), testCase.expected.signalTitles, testCase.id);
  }
});

test("shared contract: Plain English and reading time", () => {
  for (const testCase of contract.plainEnglishCases) {
    assert.equal(simplifyEnglish(testCase.input), testCase.expected);
  }
  for (const testCase of contract.readingTimeCases) {
    assert.equal(Math.max(1, Math.ceil(testCase.wordCount / 220)), testCase.expectedMinutes);
  }
});

test("shared contract: key points and claims are verbatim page text", () => {
  for (const testCase of contract.evidenceCases) {
    const page = extensionPage(testCase.page);
    const result = summarizeLocally(page);
    assert.ok(
      result.keyPoints.length > 0 || result.claimsToCheck.length > 0,
      `${testCase.id}: produced no key points or claims to verify`
    );
    for (const point of result.keyPoints) {
      assert.ok(
        testCase.page.text.includes(point),
        `${testCase.id}: key point is not verbatim page text — ${point}`
      );
    }
    for (const claim of result.claimsToCheck) {
      assert.ok(
        testCase.page.text.includes(claim),
        `${testCase.id}: claim is not verbatim page text — ${claim}`
      );
    }
    // A verbatim sentence can still be cut in the wrong place: "2.7" is one number,
    // not the end of one sentence and the start of another. Every occurrence must
    // therefore not be followed by a digit on the page.
    for (const sentence of [...result.keyPoints, ...result.claimsToCheck]) {
      if (!sentence.endsWith(".")) continue;
      let from = 0;
      let at = testCase.page.text.indexOf(sentence, from);
      while (at !== -1) {
        const next = testCase.page.text[at + sentence.length];
        assert.ok(
          !(next && /\d/.test(next)),
          `${testCase.id}: sentence ends inside a number — ${sentence}`
        );
        from = at + sentence.length;
        at = testCase.page.text.indexOf(sentence, from);
      }
    }
  }
});

test("shared contract: player interface text never reaches the reader, in any language", () => {
  for (const testCase of contract.boilerplateCases) {
    const page = extensionPage(testCase.page);
    const result = summarizeLocally(page);
    assert.ok(
      result.summary.length > 0 || result.keyPoints.length > 0,
      `${testCase.id}: produced nothing to check`
    );
    // Recognising this boilerplate must not depend on knowing the language it is
    // written in: a site that translates its player is still a site whose player
    // controls are not the article.
    const produced = [result.summary, ...result.keyPoints, ...result.claimsToCheck]
      .join(" ")
      .toLocaleLowerCase();
    for (const phrase of testCase.mustNotAppear) {
      assert.ok(
        !produced.includes(phrase.toLocaleLowerCase()),
        `${testCase.id}: player interface text reached the reader — ${phrase}`
      );
    }
  }
});

test("shared contract: a sentence the page prints twice is reported once", () => {
  for (const testCase of contract.duplicateSentenceCases) {
    const result = summarizeLocally(extensionPage(testCase.page));
    const sentence = testCase.repeatedSentence;
    // A page may print the same line twice — a headline echoed in a standfirst. It
    // is one thing the page said, so it is one thing to report.
    const inSummary = result.summary.split(sentence).length - 1;
    assert.ok(inSummary <= 1, `${testCase.id}: the gist repeats a sentence — ${sentence}`);
    assert.ok(
      result.keyPoints.filter((point) => point === sentence).length <= 1,
      `${testCase.id}: a key point is repeated — ${sentence}`
    );
  }
});

test("shared contract: a page that is only boilerplate analyses to nothing", () => {
  for (const testCase of contract.emptyAnalysisCases) {
    const result = summarizeLocally(extensionPage(testCase.page));
    // Empty, not a sentence of explanation: a user-facing string here would be
    // English on a page that is not, and belongs to the interface, not the engine.
    assert.equal(result.summary, "", `${testCase.id}: engine produced prose of its own`);
    assert.deepEqual(result.keyPoints, [], `${testCase.id}: unexpected key points`);
    assert.deepEqual(result.claimsToCheck, [], `${testCase.id}: unexpected claims`);
  }
});
