import test from "node:test";
import assert from "node:assert/strict";
import { analyzePage, assessRisk, simplifyEnglish, summarizeLocally } from "../src/core/analyzer.js";
import { compareSources } from "../src/core/compare.js";

const article = {
  title: "Cities expand shaded public spaces",
  description: "",
  text: "Cities are adding shaded public spaces as summer temperatures rise. A 2025 survey of 40 cities found that tree cover can make busy streets more comfortable. Planners say shade structures are faster to install, while mature trees provide broader environmental benefits. The report recommends measuring street temperature before and after each project. Residents also asked for more drinking fountains near transit stops.",
  wordCount: 61,
  hostname: "example.org",
  url: "https://example.org/cities",
  liveUrl: "https://example.org/cities",
  protocol: "https:",
  hasPasswordField: false,
  formActions: []
};

test("local summary returns grounded sentences and claims", () => {
  const result = summarizeLocally(article);
  assert.ok(result.summary.length > 80);
  assert.ok(result.keyPoints.length >= 1);
  assert.ok(result.claimsToCheck.some((claim) => claim.includes("2025")));
});

test("risk scan keeps ordinary HTTPS article low", () => {
  const result = assessRisk(article);
  assert.equal(result.level, "Low");
  assert.equal(result.score, 0);
});

test("risk scan elevates password and secret-request signals", () => {
  const result = assessRisk({
    ...article,
    protocol: "http:",
    url: "http://192.168.1.8/login",
    liveUrl: "http://192.168.1.8/login",
    hostname: "192.168.1.8",
    hasPasswordField: true,
    text: "Act immediately. Send your recovery phrase to restore the account."
  });
  assert.equal(result.level, "High");
  assert.ok(result.score >= 80);
  assert.ok(result.signals.length >= 3);
});

test("plain English mode replaces common formal wording", () => {
  assert.equal(simplifyEnglish("Individuals utilize numerous tools."), "people use many tools.");
});

test("full analysis estimates read time", () => {
  const result = analyzePage({ ...article, wordCount: 660 });
  assert.equal(result.readMinutes, 3);
  assert.equal(result.mode, "Local");
});

test("comparison exposes overlap without claiming agreement", () => {
  const result = compareSources(
    { title: "City shade plans", summary: "Cities add trees and shade.", keyPoints: ["The plan covers transit stops."] },
    { title: "Shade in cities", summary: "New trees bring shade to streets.", keyPoints: ["Transit riders want shade."] }
  );
  assert.ok(result.overlapPercent > 0);
  assert.match(result.note, /not factual agreement/i);
});
