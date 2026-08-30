import test from "node:test";
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import {
  assessRisk,
  splitSentences,
  assessStructure,
  readableText
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

test("shared contract: reading time", () => {
  for (const testCase of contract.readingTimeCases) {
    assert.equal(Math.max(1, Math.ceil(testCase.wordCount / 220)), testCase.expectedMinutes);
  }
});

test("shared contract: player interface text never reaches the readable text, in any language", () => {
  for (const testCase of contract.boilerplateCases) {
    const text = readableText(extensionPage(testCase.page)).toLocaleLowerCase();
    assert.ok(text.length > 0, `${testCase.id}: produced nothing to check`);
    // Recognising this boilerplate must not depend on knowing the language it is
    // written in: a site that translates its player is still a site whose player
    // controls are not the article.
    for (const phrase of testCase.mustNotAppear) {
      assert.ok(
        !text.includes(phrase.toLocaleLowerCase()),
        `${testCase.id}: player interface text survived — ${phrase}`
      );
    }
  }
});

test("shared contract: a sentence the page prints twice is kept once", () => {
  for (const testCase of contract.duplicateSentenceCases) {
    const text = readableText(extensionPage(testCase.page));
    const sentence = testCase.repeatedSentence;
    // A page may print the same line twice — a headline echoed in a standfirst. It
    // is one thing the page said, so it is copied once.
    assert.ok(
      text.split(sentence).length - 1 <= 1,
      `${testCase.id}: the readable text repeats a sentence — ${sentence}`
    );
  }
});

test("shared contract: a page that is only boilerplate reduces to nothing", () => {
  for (const testCase of contract.emptyAnalysisCases) {
    // Empty, not a sentence of explanation: a user-facing string here would be
    // English on a page that is not, and belongs to the interface, not the engine.
    assert.equal(
      readableText(extensionPage(testCase.page)), "",
      `${testCase.id}: engine produced text of its own`
    );
  }
});

test("shared contract: sentences split the same way in both runtimes", () => {
  for (const testCase of contract.segmentationCases) {
    assert.deepEqual(
      splitSentences(testCase.text, testCase.language),
      testCase.expected,
      `${testCase.id}: split differently`
    );
  }
});
