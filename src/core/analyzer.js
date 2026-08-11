const STOP_WORDS = new Set(
  "a an and are as at be been but by can could did do does for from had has have he her hers him his how i if in into is it its may might more most must my no not of on one or our ours she should so some than that the their theirs them then there these they this those to too us was we were what when where which who why will with would you your yours about after again against all am any because before being below between both during each few further here itself just many me nor now off once only other out over own same such through under until up very we while".split(
    " "
  )
);

const PLAIN_REPLACEMENTS = new Map([
  ["approximately", "about"],
  ["additional", "more"],
  ["commence", "start"],
  ["consequently", "so"],
  ["demonstrate", "show"],
  ["facilitate", "help"],
  ["individuals", "people"],
  ["in order to", "to"],
  ["numerous", "many"],
  ["purchase", "buy"],
  ["regarding", "about"],
  ["subsequently", "later"],
  ["utilize", "use"]
]);

export function normalizeText(value = "") {
  return value.replace(/\s+/g, " ").trim();
}

export function splitSentences(value = "") {
  return (
    normalizeText(value).match(/[^.!?。！？]+[.!?。！？]+|[^.!?。！？]+$/g) || []
  )
    .map((sentence) => normalizeText(sentence))
    .filter((sentence) => sentence.length >= 35 && sentence.length <= 520);
}

export function tokenize(value = "") {
  return (value.toLowerCase().match(/[\p{L}\p{N}][\p{L}\p{N}'’-]*/gu) || []).filter(
    (word) => word.length >= 3 && !STOP_WORDS.has(word)
  );
}

function sentenceScores(sentences, title = "") {
  const frequencies = new Map();
  const titleWords = new Set(tokenize(title));

  for (const word of tokenize(sentences.join(" "))) {
    frequencies.set(word, (frequencies.get(word) || 0) + 1);
  }

  const maxFrequency = Math.max(1, ...frequencies.values());
  return sentences.map((sentence, index) => {
    const words = tokenize(sentence);
    const topicality = words.reduce(
      (score, word) => score + (frequencies.get(word) || 0) / maxFrequency,
      0
    );
    const titleOverlap = words.filter((word) => titleWords.has(word)).length * 0.7;
    const leadBonus = index < 3 ? 0.8 - index * 0.2 : 0;
    const lengthPenalty = words.length < 7 || words.length > 48 ? 0.7 : 1;

    return {
      sentence,
      index,
      score: ((topicality + titleOverlap) / Math.sqrt(Math.max(words.length, 1)) + leadBonus) * lengthPenalty
    };
  });
}

function selectSentences(scored, count) {
  return scored
    .slice()
    .sort((a, b) => b.score - a.score)
    .slice(0, count)
    .sort((a, b) => a.index - b.index)
    .map((entry) => entry.sentence);
}

export function summarizeLocally(page) {
  const source = normalizeText(page.text || page.description || "");
  const sentences = splitSentences(source);

  if (!sentences.length) {
    return {
      summary: page.description || "There is not enough readable text on this page to summarize.",
      keyPoints: [],
      claimsToCheck: []
    };
  }

  const scored = sentenceScores(sentences, page.title);
  const summarySentences = selectSentences(scored, Math.min(3, sentences.length));
  const summarySet = new Set(summarySentences);
  const keyPoints = scored
    .slice()
    .sort((a, b) => b.score - a.score)
    .filter((entry) => !summarySet.has(entry.sentence))
    .slice(0, 4)
    .map((entry) => entry.sentence);

  const claimPattern =
    /\b(according|report|study|research|survey|million|billion|percent|guarantee|always|never|only|best|worst|first)\b|\d[%\d,.:/-]*/i;
  const claimsToCheck = scored
    .filter((entry) => claimPattern.test(entry.sentence))
    .sort((a, b) => b.score - a.score)
    .slice(0, 3)
    .map((entry) => entry.sentence);

  return {
    summary: summarySentences.join(" "),
    keyPoints,
    claimsToCheck
  };
}

export function assessRisk(page) {
  const signals = [];
  let score = 0;
  const host = page.hostname || "";
  const text = (page.text || "").slice(0, 30000).toLowerCase();

  const addSignal = (points, title, detail) => {
    score += points;
    signals.push({ points, title, detail });
  };

  if (page.protocol !== "https:") {
    addSignal(20, "Connection is not encrypted", "Information sent to this page may be exposed in transit.");
  }

  if (page.hasPasswordField && page.protocol !== "https:") {
    addSignal(40, "Password requested on an unencrypted page", "Do not enter a password here.");
  }

  if (host.startsWith("xn--") || host.includes(".xn--")) {
    addSignal(25, "Encoded domain name", "Internationalized domains can be legitimate, but also deserve a closer look.");
  }

  if (/^(\d{1,3}\.){3}\d{1,3}$/.test(host)) {
    addSignal(20, "Site uses a raw IP address", "Most consumer services use a recognizable domain name.");
  }

  let origin = "";
  try {
    origin = new URL(page.liveUrl || page.url).origin;
  } catch {
    origin = "";
  }
  if (page.formActions?.some((action) => action && origin && action !== origin)) {
    addSignal(15, "A form sends data to another site", "That can be normal for payments, but confirm the destination before submitting.");
  }

  const patterns = [
    {
      regex: /seed phrase|recovery phrase|private key/,
      points: 35,
      title: "Requests a wallet secret",
      detail: "Legitimate support should never ask for a seed phrase or private key."
    },
    {
      regex: /gift card|wire transfer|pay in (bitcoin|crypto)|send (bitcoin|crypto)/,
      points: 18,
      title: "Hard-to-reverse payment language",
      detail: "Gift cards, wire transfers, and crypto payments are common in scams."
    },
    {
      regex: /guaranteed returns|double your money|risk[- ]free investment/,
      points: 25,
      title: "Implausible financial promise",
      detail: "Guaranteed or risk-free returns are a serious warning sign."
    },
    {
      regex: /account (will be|is) (closed|suspended)|act (now|immediately)|final warning/,
      points: 10,
      title: "Urgency or account-threat language",
      detail: "Pressure to act immediately can be used to prevent careful checking."
    },
    {
      regex: /anydesk|teamviewer|remote desktop|remote access/,
      points: 18,
      title: "Remote-access language",
      detail: "Unexpected requests to install remote-access software are high risk."
    }
  ];

  for (const pattern of patterns) {
    if (pattern.regex.test(text)) {
      addSignal(pattern.points, pattern.title, pattern.detail);
    }
  }

  const cappedScore = Math.min(score, 100);
  return {
    score: cappedScore,
    level: cappedScore >= 40 ? "High" : cappedScore >= 20 ? "Caution" : "Low",
    signals,
    secureConnection: page.protocol === "https:"
  };
}

export function simplifyEnglish(value = "") {
  let result = normalizeText(value);
  for (const [complex, plain] of PLAIN_REPLACEMENTS) {
    result = result.replace(new RegExp(`\\b${complex}\\b`, "gi"), plain);
  }

  const sentences = splitSentences(result);
  if (!sentences.length) return result;

  return sentences
    .flatMap((sentence) => {
      if (sentence.length < 220) return [sentence];
      const parts = sentence.split(/; |, (?:and|but|while|which) /i).map(normalizeText);
      return parts.length > 1 ? parts.map((part) => (/[.!?]$/.test(part) ? part : `${part}.`)) : [sentence];
    })
    .join(" ");
}

export function analyzePage(page) {
  const summary = summarizeLocally(page);
  return {
    ...summary,
    risk: assessRisk(page),
    readMinutes: Math.max(1, Math.round((page.wordCount || 0) / 220)),
    mode: "Local",
    analyzedAt: new Date().toISOString()
  };
}
