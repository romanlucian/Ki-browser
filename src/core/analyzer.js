const wordSet = (value) => new Set(value.split(" "));
const STOP_WORDS_BY_LANGUAGE = {
  en: wordSet("a an and are as at be been but by can could did do does for from had has have he her hers him his how i if in into is it its may might more most must my no not of on one or our ours she should so some than that the their theirs them then there these they this those to too us was we were what when where which who why will with would you your yours about after again against all am any because before being below between both during each few further here itself just many me nor now off once only other out over own same such through under until up very while"),
  ro: wordSet("acela acea aceea acest aceasta aceste acești ale al ai așa ca care către când cea cei cele cel ce cu cum de din după este fi fost iar în între la mai nici nu o pe pentru prin sau se și sunt un una unei unui vor"),
  fr: wordSet("alors au aux avec ce ces comme dans de des du elle en est et eux il ils je la le les leur lui ma mais me même mes moi mon ne nos notre nous on ou par pas pour qu que quelle qui sa se ses son sont sur ta te tes toi ton tu un une vos votre vous c d j l à ça était été être"),
  zh: wordSet("也 个 中 为 了 与 及 和 在 对 将 是 有 的 而 这 那")
};
const FALLBACK_STOP_WORDS = new Set(Object.values(STOP_WORDS_BY_LANGUAGE).flatMap((words) => [...words]));

function stopWordsFor(language = "") {
  const primary = language.trim().toLocaleLowerCase().split(/[-_]/u)[0];
  return STOP_WORDS_BY_LANGUAGE[primary] || FALLBACK_STOP_WORDS;
}

const MEDIA_INTERFACE_PHRASES = [
  "subtitles settings, opens subtitles settings dialog",
  "captions settings, opens captions settings dialog",
  "video player is loading",
  "audio player is loading",
  "stream type live",
  "seek to live, currently behind live",
  "playback controls",
  "playback rate",
  "picture-in-picture"
];

const CJK_PATTERN = /[\p{Script=Han}\p{Script=Hiragana}\p{Script=Katakana}\p{Script=Hangul}]/u;

// Structure thresholds calibrated on live English and Romanian section fronts and
// articles. Simplified Chinese has no listing measurement yet; only the shorter CJK
// block length follows the analyzer's existing CJK-aware precedent.
const BLOCK_ENDING_PATTERN = /[.!?…。！？:;]$/u;
const MINIMUM_LISTING_BLOCKS = 12;
const LISTING_END_PUNCTUATION_PERCENT = 60;
const LISTING_PROSE_MASS_PERCENT = 10;
const LONG_BLOCK_CHARACTERS = 220;
const LONG_CJK_BLOCK_CHARACTERS = 100;

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
    .filter((sentence) => sentence.length >= (CJK_PATTERN.test(sentence) ? 12 : 35) && sentence.length <= 520);
}

export function tokenize(value = "", language = "") {
  const result = [];
  let current = "";
  const stopWords = stopWordsFor(language);
  const appendCurrent = () => {
    if (current.length >= 2 && !stopWords.has(current)) result.push(current);
    current = "";
  };

  for (const character of value.toLocaleLowerCase()) {
    if (CJK_PATTERN.test(character)) {
      appendCurrent();
      if (!stopWords.has(character)) result.push(character);
    } else if (/[\p{L}\p{M}\p{N}'’-]/u.test(character)) {
      current += character;
    } else {
      appendCurrent();
    }
  }
  appendCurrent();
  return result;
}

function normalizeReadingBlocks(value = "") {
  const blocks = value.split(/\r?\n/).map(normalizeText).filter(Boolean);
  if (blocks.length <= 1) return normalizeText(value);
  return blocks.map((block) => /[.!?。！？:;]$/u.test(block) ? block : `${block}.`).join(" ");
}

function removeRepeatedMediaInterfaceText(value = "") {
  const lower = value.toLocaleLowerCase();
  const controlMatchCount = MEDIA_INTERFACE_PHRASES.reduce((count, phrase) => {
    return count + lower.split(phrase).length - 1;
  }, 0);
  if (controlMatchCount < 2) return value;
  return MEDIA_INTERFACE_PHRASES.reduce(
    (result, phrase) => result.replaceAll(new RegExp(phrase.replace(/[.*+?^${}()|[\]\\]/g, "\\$&"), "gi"), " "),
    value
  );
}

function sentenceScores(sentences, title = "", language = "") {
  const frequencies = new Map();
  const titleWords = new Set(tokenize(title, language));

  for (const word of tokenize(sentences.join(" "), language)) {
    frequencies.set(word, (frequencies.get(word) || 0) + 1);
  }

  const maxFrequency = Math.max(1, ...frequencies.values());
  return sentences.map((sentence, index) => {
    const words = tokenize(sentence, language);
    const topicality = words.reduce(
      (score, word) => score + (frequencies.get(word) || 0) / maxFrequency,
      0
    );
    const titleOverlap = words.filter((word) => titleWords.has(word)).length * 0.7;
    const leadBonus = index < 3 ? 0.8 - index * 0.2 : 0;
    const maximumUsefulTokens = CJK_PATTERN.test(sentence) ? 100 : 48;
    const lengthPenalty = words.length < 7 || words.length > maximumUsefulTokens ? 0.7 : 1;

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
  const source = normalizeReadingBlocks(
    removeRepeatedMediaInterfaceText(page.text || page.description || "")
  );
  const sentences = splitSentences(source);

  if (!sentences.length) {
    return {
      summary: page.description || "There is not enough readable text on this page to summarize.",
      keyPoints: [],
      claimsToCheck: []
    };
  }

  const scored = sentenceScores(sentences, page.title, page.language);
  const summarySentences = selectSentences(scored, Math.min(3, sentences.length));
  const summarySet = new Set(summarySentences);
  const keyPoints = scored
    .slice()
    .sort((a, b) => b.score - a.score)
    .filter((entry) => !summarySet.has(entry.sentence))
    .slice(0, 4)
    .map((entry) => entry.sentence);

  const claimPattern =
    /\b(according|report|study|research|survey|million|billion|percent|guarantee|always|never|only|best|worst|first|potrivit|raport|studiu|cercetare|sondaj|milioane|miliarde|procent|selon|rapport|étude|recherche|sondage|milliard|pour cent)\b|报告|研究|调查|百万|十亿|百分之|保证|最佳|首次|\d[%\d,.:/-]*/iu;
  // A claim repeated from the gist or a key point gives the reader nothing new to
  // check, so keep claims to sentences the rest of the result did not already show.
  const presentedSentences = new Set([...summarySentences, ...keyPoints]);
  const claimsToCheck = scored
    .filter((entry) => !presentedSentences.has(entry.sentence) && claimPattern.test(entry.sentence))
    .sort((a, b) => b.score - a.score)
    .slice(0, 3)
    .map((entry) => entry.sentence);

  return {
    summary: summarySentences.join(" "),
    keyPoints,
    claimsToCheck
  };
}

// A section or index page stitches unrelated headlines into a confident-looking
// summary, so the interface has to know what kind of page it is looking at. Read the
// extractor's reading blocks: many blocks, few sentence endings, and almost no long
// punctuated prose describe a list of links rather than a text to summarize. Article
// stays the safe default — including the single-block extractor fallback — because
// hiding a real summary costs the reader more than summarizing a list.
export function assessStructure(page) {
  const blocks = (page.text || "").split(/\r?\n/).map(normalizeText).filter(Boolean);
  if (blocks.length < MINIMUM_LISTING_BLOCKS) return "article";

  let punctuatedBlocks = 0;
  let totalCharacters = 0;
  let longPunctuatedCharacters = 0;
  for (const block of blocks) {
    const isPunctuated = BLOCK_ENDING_PATTERN.test(block);
    const longBlock = CJK_PATTERN.test(block) ? LONG_CJK_BLOCK_CHARACTERS : LONG_BLOCK_CHARACTERS;
    totalCharacters += block.length;
    if (isPunctuated) punctuatedBlocks += 1;
    if (isPunctuated && block.length >= longBlock) longPunctuatedCharacters += block.length;
  }

  // Compare the two shares as integers so both runtimes agree on the boundaries.
  const mostlyUnpunctuated = punctuatedBlocks * 100 < blocks.length * LISTING_END_PUNCTUATION_PERCENT;
  const littleProseMass = longPunctuatedCharacters * 100 < totalCharacters * LISTING_PROSE_MASS_PERCENT;
  return mostlyUnpunctuated && littleProseMass ? "listing" : "article";
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

  const unwrappedHost = host.replace(/^\[|\]$/g, "");
  const octets = unwrappedHost.split(".");
  const isIPv4 = octets.length === 4 && octets.every(
    (part) => /^\d{1,3}$/.test(part) && Number(part) >= 0 && Number(part) <= 255
  );
  const compressionParts = unwrappedHost.split("::");
  const ipv6Groups = unwrappedHost.split(":").filter(Boolean);
  let representedGroupCount = 0;
  let validGroups = true;
  ipv6Groups.forEach((group, index) => {
    if (group.includes(".")) {
      const embeddedOctets = group.split(".");
      const validEmbeddedIPv4 = embeddedOctets.length === 4 && embeddedOctets.every(
        (part) => /^\d{1,3}$/.test(part) && Number(part) >= 0 && Number(part) <= 255
      );
      validGroups &&= index === ipv6Groups.length - 1 && validEmbeddedIPv4;
      representedGroupCount += 2;
    } else {
      validGroups &&= /^[0-9a-f]{1,4}$/i.test(group);
      representedGroupCount += 1;
    }
  });
  const isIPv6 = unwrappedHost.includes(":") &&
    !unwrappedHost.includes(":::") &&
    compressionParts.length <= 2 &&
    validGroups &&
    (compressionParts.length === 2 ? representedGroupCount < 8 : representedGroupCount === 8);
  if (isIPv4 || isIPv6) {
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
    }
  ];

  for (const pattern of patterns) {
    if (pattern.regex.test(text)) {
      addSignal(pattern.points, pattern.title, pattern.detail);
    }
  }
  if (containsContextualRemoteAccessRequest(text)) {
    addSignal(
      20,
      "Remote-access request",
      "The page combines remote-access software with instructions and pressure or support/payment context. Confirm the request independently before continuing."
    );
  }

  const cappedScore = Math.min(score, 100);
  return {
    score: cappedScore,
    level: cappedScore >= 40 ? "High" : cappedScore >= 20 ? "Caution" : "Low",
    signals,
    secureConnection: page.protocol === "https:"
  };
}

function containsContextualRemoteAccessRequest(text) {
  const remotePattern = /\b(?:anydesk|teamviewer|remote desktop|remote access)\b/giu;
  const actionPattern = /\b(?:install|download|open|run|launch|connect|allow|grant|give|provide|share|enable)\b/iu;
  const contextPattern = /\b(?:support|technician|refund|bank|payment|account|security alert|virus|infected|immediately|urgent|now|verify|call)\b/iu;

  for (const match of text.matchAll(remotePattern)) {
    const start = Math.max(0, match.index - 180);
    const end = Math.min(text.length, match.index + match[0].length + 180);
    const window = text.slice(start, end);
    if (actionPattern.test(window) && contextPattern.test(window)) return true;
  }
  return false;
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

export function canSimplifyToPlainEnglish(language = "") {
  const normalized = language.trim().toLowerCase();
  return normalized === "en" || normalized.startsWith("en-") || normalized.startsWith("en_");
}

export function analyzePage(page) {
  const summary = summarizeLocally(page);
  return {
    ...summary,
    risk: assessRisk(page),
    readMinutes: Math.max(1, Math.ceil((page.wordCount || 0) / 220)),
    mode: "Local",
    analyzedAt: new Date().toISOString()
  };
}
