import test from "node:test";
import assert from "node:assert/strict";
import {
  analyzePage,
  assessRisk,
  readableText
} from "../src/core/analyzer.js";

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

test("readable text treats rendered blocks as boundaries and removes repeated player UI", () => {
  const text = readableText({
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

  assert.ok(text.length > 80);
  // The Romanian prose survives; the player's English control strings do not.
  assert.match(text, /Primăria extinde zonele umbrite/);
  assert.doesNotMatch(text, /video player|stream type|playback controls/i);
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

test("full analysis estimates read time", () => {
  const result = analyzePage({ ...article, wordCount: 660 });
  assert.equal(result.readMinutes, 3);
});

test("read time rounds partial minutes up", () => {
  assert.equal(analyzePage({ ...article, wordCount: 221 }).readMinutes, 2);
});
