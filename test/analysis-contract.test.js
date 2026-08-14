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
