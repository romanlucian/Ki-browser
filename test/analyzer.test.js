import test from "node:test";
import assert from "node:assert/strict";
import {
  analyzePage,
  assessRisk,
  canSimplifyToPlainEnglish,
  simplifyEnglish,
  summarizeLocally,
  tokenize
} from "../src/core/analyzer.js";
import { compareSources } from "../src/core/compare.js";

const article = {
  title: "Cities expand shaded public spaces",
  description: "",
  text: "Cities are adding shaded public spaces as summer temperatures rise. A 2025 survey of 40 cities found that tree cover can make busy streets more comfortable. Planners say shade structures are faster to install, while mature trees provide broader environmental benefits. The report recommends measuring street temperature before and after each project. Residents also asked for more drinking fountains near transit stops. Maintenance crews water young trees twice a week through the first summer. The city budget sets aside money for replacing damaged shade fabric each year. Volunteers mapped every bench in the market district last autumn. Officials plan to publish the temperature readings on an open data page. An earlier pilot in 2019 covered only three streets, according to the appendix.",
  wordCount: 122,
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
  assert.ok(result.claimsToCheck.some((claim) => claim.includes("report")));
});

test("claims never repeat the summary or key points", () => {
  const result = summarizeLocally(article);
  assert.ok(result.claimsToCheck.length >= 1);
  for (const claim of result.claimsToCheck) {
    assert.ok(!result.summary.includes(claim), `claim repeated the gist: ${claim}`);
    assert.ok(!result.keyPoints.includes(claim), `claim repeated a key point: ${claim}`);
  }
});

test("English topic words are not removed by other-language stopwords", () => {
  const tokens = tokenize(
    "The new health care law will care for children and their care needs. A son and his father discussed care options.",
    "en-US"
  );

  assert.equal(tokens.filter((token) => token === "care").length, 4);
  assert.ok(tokens.includes("son"));
  assert.ok(!tokens.includes("the"));
  assert.ok(!tokenize("son sont avec", "fr").includes("son"));
});

test("local summary preserves short Simplified Chinese sentences and claims", () => {
  const result = summarizeLocally({
    ...article,
    title: "城市遮阴计划",
    language: "zh-CN",
    text: "多个城市正在增加公共遮阴空间。2025年的调查覆盖了四十个城市。成熟树木可以提供更广泛的环境效益。报告建议在项目实施前后测量街道温度。居民还要求在交通站点附近增加饮水设施。养护人员在第一个夏天每周浇水两次。市政预算每年安排更换损坏的遮阳布。志愿者去年秋天记录了市场区的每一张长椅。官员计划在公开数据页面发布温度记录。附录提到2019年的试点只覆盖了三条街道。"
  });

  assert.match(result.summary, /城市|调查|报告/u);
  assert.ok(result.keyPoints.length >= 1);
  assert.ok(result.claimsToCheck.some((claim) => /调查|报告|2025/u.test(claim)));
});

test("local summary treats rendered blocks as boundaries and removes repeated player UI", () => {
  const result = summarizeLocally({
    ...article,
    language: "ro",
    text: [
      "Primăria extinde zonele umbrite pentru că verile devin mai fierbinți",
      "Un sondaj din 2025 a inclus patruzeci de orașe și recomandă măsurători locale",
      "Locuitorii cer fântâni de apă aproape de stațiile de transport public",
      "Planificatorii vor publica programul de întreținere pentru fiecare proiect",
      "Copacii maturi oferă umbră densă pe străzile aglomerate din centrul orașului",
      "Zonele umbrite din piață vor fi extinse și în cartierele mărginașe ale orașului",
      "Orașul va planta copaci noi lângă stațiile de transport aglomerate",
      "Echipele de întreținere udă copacii tineri de două ori pe săptămână vara",
      "Voluntarii au cartografiat băncile umbrite din piață în toamna trecută",
      "Un proiect pilot din 2019 a acoperit doar trei străzi, potrivit anexei",
      "Video Player is loading Stream Type LIVE Playback controls"
    ].join("\n")
  });

  assert.ok(result.summary.length > 80);
  assert.ok(result.claimsToCheck.some((claim) => /2019|potrivit/i.test(claim)));
  assert.ok(!result.claimsToCheck.some((claim) => result.summary.includes(claim)));
  assert.doesNotMatch(`${result.summary} ${result.keyPoints.join(" ")}`, /video player|stream type|playback controls/i);
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

test("risk scan validates IPv4 octets and recognizes IPv6", () => {
  const invalid = assessRisk({
    ...article,
    hostname: "999.999.999.999",
    url: "https://999.999.999.999/article",
    liveUrl: "https://999.999.999.999/article"
  });
  assert.equal(invalid.signals.some((signal) => /raw IP/i.test(signal.title)), false);

  const invalidIPv6 = assessRisk({
    ...article,
    hostname: "::::",
    url: "https://example.org/article",
    liveUrl: "https://example.org/article"
  });
  assert.equal(invalidIPv6.signals.some((signal) => /raw IP/i.test(signal.title)), false);

  const ipv6 = assessRisk({
    ...article,
    hostname: "[2001:db8::1]",
    protocol: "http:",
    url: "http://[2001:db8::1]/article",
    liveUrl: "http://[2001:db8::1]/article"
  });
  assert.equal(ipv6.signals.some((signal) => /raw IP/i.test(signal.title)), true);
});

test("plain English mode replaces common formal wording", () => {
  assert.equal(simplifyEnglish("Individuals utilize numerous tools."), "people use many tools.");
});

test("local Plain English is limited to English source labels", () => {
  assert.equal(canSimplifyToPlainEnglish("en-US"), true);
  assert.equal(canSimplifyToPlainEnglish("fr"), false);
  assert.equal(canSimplifyToPlainEnglish("ro-RO"), false);
  assert.equal(canSimplifyToPlainEnglish(""), false);
});

test("full analysis estimates read time", () => {
  const result = analyzePage({ ...article, wordCount: 660 });
  assert.equal(result.readMinutes, 3);
  assert.equal(result.mode, "Local");
});

test("read time rounds partial minutes up", () => {
  assert.equal(analyzePage({ ...article, wordCount: 221 }).readMinutes, 2);
});

test("comparison exposes overlap without claiming agreement", () => {
  const result = compareSources(
    { title: "City shade plans", summary: "Cities add trees and shade.", keyPoints: ["The plan covers transit stops."] },
    { title: "Shade in cities", summary: "New trees bring shade to streets.", keyPoints: ["Transit riders want shade."] }
  );
  assert.ok(result.overlapPercent > 0);
  assert.match(result.note, /not factual agreement/i);
});
