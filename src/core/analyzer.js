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

// Swift counts `Character`s — extended grapheme clusters — so JavaScript has to
// count the same units or the two runtimes measure different sentences.
//
// `.length` counts UTF-16 units, which double-counts a combining accent and every
// astral character. The same French sentence written in decomposed form measures 73
// there and 53 here, so identical control text looks like a smaller share of it and
// only one runtime calls it player interface. UAX#29 grapheme segmentation is what
// `Character` means, so it is what this uses.
const GRAPHEME_SEGMENTER = new Intl.Segmenter("en", { granularity: "grapheme" });

// Segmentation is exact and costs more than the rest of the analysis put together,
// and this runs for every candidate sentence on the page. Most text does not need
// it — but deciding which by listing what breaks clustering was wrong. That list
// named astral characters, combining marks, the zero-width joiner and Hangul jamo,
// and missed the zero-width NON-joiner that ordinary Persian is full of, so
// "\u0645\u06CC\u200C\u0634\u0648\u062F" counted six where a reader sees five. It also missed the
// Prepend class and a carriage return before a newline. Unicode can add to those
// categories; it cannot be enumerated safely from the outside.
//
// The test is inverted instead. The fast path is taken only for text made entirely
// of characters checked to be a grapheme of their own and never to cluster with a
// neighbour — 21,936 of them, verified against the segmenter itself. Everything
// else segments. Being narrow costs little: the scripts that fall through are the
// ones that genuinely need segmenting, and they are still faster than before.
const STANDALONE_GRAPHEME_PATTERN =
  /^[\t\n\u0020-\u007E\u00A0-\u024F\u2010-\u2027\u2030-\u205E\u3000-\u3029\u3030-\u3098\u309B-\u30FF\u4E00-\u9FFF\uFF01-\uFF60]*$/u;

function graphemeCount(value) {
  if (STANDALONE_GRAPHEME_PATTERN.test(value)) return value.length;
  return [...GRAPHEME_SEGMENTER.segment(value)].length;
}

// Written as explicit ranges rather than `\p{Script=...}`, because Swift has no
// script property and tests scalar ranges by hand. The two lists must be the same
// list: this decides the minimum length of a sentence and the size a block must
// reach to count as a paragraph, so a character one runtime calls CJK and the
// other does not gives the two different answers about the same page.
const CJK_PATTERN = /[\u1100-\u11FF\u2E80-\u2EFF\u2F00-\u2FDF\u3005\u3007\u3040-\u30FF\u3130-\u318F\u31F0-\u31FF\u3400-\u4DBF\u4E00-\u9FFF\uA960-\uA97F\uAC00-\uD7AF\uD7B0-\uD7FF\uF900-\uFAFF\uFF66-\uFF9F]|[\u{20000}-\u{3134F}]|[\u{2F800}-\u{2FA1F}]/u;

// Structure thresholds calibrated on live English and Romanian section fronts and
// articles. Simplified Chinese has no listing measurement yet; only the shorter CJK
// block length follows the analyzer's existing CJK-aware precedent.
// Sentence terminators Clearframe recognises. Latin and CJK stops, plus the Devanagari
// danda and double danda, the Urdu full stop, and the Arabic question mark. A script
// whose terminator is missing here reads as one endless sentence, which also makes its
// pages look unpunctuated to assessStructure.
const SENTENCE_ENDING_CHARACTERS = new Set([
  ".", "!", "?", "。", "！", "？", "।", "॥", "۔", "؟", "։"
]);
// Mirrors Swift's Character.isLowercase, which is the Unicode **Lowercase**
// binary property — Ll plus Other_Lowercase. Not \p{Ll}: that is the general
// category alone and excludes the ordinal indicators Spanish and Portuguese use
// in ordinary prose, so "Vive en el 5.º piso" split here and not in Swift, and
// this runtime then dropped the short half and reported a sentence starting "º".
const LOWERCASE_PATTERN = /\p{Lowercase}/u;
const LEADING_NON_WORD_PATTERN = /^[^\p{L}\p{N}]+/u;
const LETTER_PATTERN = /\p{L}/u;

// Words that take a full stop without ending a sentence. Keyed by language and
// never merged into one set: Italian "es." abbreviates esempio, while Spanish
// "es" is the verb, so an Italian entry loose in a Spanish page would swallow the
// boundary after "Así es." An unrecognised language gets an empty set — no
// joining rather than another language's guesses.
const abbreviationSet = (value) => new Set(value.split(" "));
const SENTENCE_ABBREVIATIONS_BY_LANGUAGE = {
  en: abbreviationSet("mr mrs ms dr prof sr jr st vs etc inc ltd corp fig vol pp ed al approx dept jan feb mar apr jun jul aug sep sept oct nov dec e.g i.e u.s u.k"),
  ro: abbreviationSet("dl dna dr ing nr ex etc pag vol art"),
  fr: abbreviationSet("m mme mlle dr pr st ste av ex etc vol pp"),
  es: abbreviationSet("sr sra srta dr dra prof ud uds etc núm pág vol"),
  de: abbreviationSet("hr dr prof bzw ca evtl ggf inkl usw vgl nr abs z u d"),
  it: abbreviationSet("sig dott dr prof avv ecc pag vol num es")
};

function abbreviationsFor(language = "") {
  const primary = language.trim().toLowerCase().split(/[-_]/u)[0];
  return SENTENCE_ABBREVIATIONS_BY_LANGUAGE[primary] || new Set();
}

// The word a period follows, so "(e.g." asks about "e.g" and "Dr." about "dr".
function trailingWord(value) {
  const withoutTerminator = value.slice(0, -1);
  const word = withoutTerminator.slice(withoutTerminator.lastIndexOf(" ") + 1);
  return word.replace(LEADING_NON_WORD_PATTERN, "").toLowerCase();
}

function periodEndsSentence(current, characters, index, abbreviations) {
  let next = index + 1;
  while (next < characters.length && characters[next] === " ") next += 1;
  if (next >= characters.length) return true;
  const following = characters[next];
  // "e.g. scheduling", "U.S. policy", "approx. 15" — nothing starts a sentence
  // with a lowercase letter or a digit, so that stop belonged to the word.
  if (LOWERCASE_PATTERN.test(following) || NUMERIC_PATTERN.test(following)) return false;
  const word = trailingWord(current);
  // "U.S. policy", "J. R. R. Tolkien" — a lone letter before a stop is an initial,
  // not the end of a thought. Counted in graphemes, as Swift counts Characters.
  if (graphemeCount(word) === 1 && LETTER_PATTERN.test(word)) return false;
  // A capital follows, so only a known abbreviation joins them: "Dr. Alison" is
  // one sentence and "the office. Analysts" is two.
  return !abbreviations.has(word);
}
// Mirrors Swift's Character.isNumber, which covers Nd, Nl and No — Devanagari and
// full-width digits included. Not \d, which is ASCII only.
const NUMERIC_PATTERN = /\p{N}/u;
const BLOCK_ENDING_PATTERN = /[.!?…。！？:;।॥۔؟]$/u;
const MINIMUM_LISTING_BLOCKS = 12;
const LISTING_END_PUNCTUATION_PERCENT = 60;
const LISTING_PROSE_MASS_PERCENT = 10;
const LONG_BLOCK_CHARACTERS = 220;
const LONG_CJK_BLOCK_CHARACTERS = 100;

export function normalizeText(value = "") {
  return value.replace(/\s+/g, " ").trim();
}

function isUsefulSentenceLength(sentence) {
  const minimum = CJK_PATTERN.test(sentence) ? 12 : 35;
  // Graphemes, matching Swift's `count`. UTF-16 length is an upper bound on the
  // grapheme count, so anything short by that measure is certainly short, and the
  // segmenter is only worth running once that cheap test has passed.
  if (sentence.length < minimum) return false;
  const characters = graphemeCount(sentence);
  return characters >= minimum && characters <= 520;
}

export function splitSentences(value = "", language = "") {
  const characters = [...normalizeText(value)];
  const abbreviations = abbreviationsFor(language);
  const sentences = [];
  let current = "";

  for (let index = 0; index < characters.length; index += 1) {
    const character = characters[index];
    current += character;
    if (!SENTENCE_ENDING_CHARACTERS.has(character)) continue;
    // "2.7" is a single number, not the end of one sentence and the start of
    // another. Only a period between two digits is ambiguous this way.
    // \p{N}, not \d: Swift's Character.isNumber is true for every Unicode numeric,
    // so an ASCII-only test here would split "२.५" and "２.７" in this runtime while
    // the Swift engine kept them whole. The two must agree character for character.
    if (
      character === "." &&
      index > 0 &&
      index + 1 < characters.length &&
      NUMERIC_PATTERN.test(characters[index - 1]) &&
      NUMERIC_PATTERN.test(characters[index + 1])
    ) {
      continue;
    }
    if (character === "." && !periodEndsSentence(current, characters, index, abbreviations)) {
      continue;
    }
    const sentence = normalizeText(current);
    if (isUsefulSentenceLength(sentence)) sentences.push(sentence);
    current = "";
  }

  const remainder = normalizeText(current);
  if (isUsefulSentenceLength(remainder)) sentences.push(remainder);
  return sentences;
}

// The browser extractor separates rendered reading blocks with newlines, and a block
// boundary is a sentence boundary. Splitting per block keeps unrelated headlines from
// fusing into one oversized point without inventing terminal punctuation — an invented
// character would leave the sentence unfindable on the live page, which is exactly what
// Evidence Mode searches for.
function sentencesFromReadingBlocks(value = "", language = "") {
  return value.split(/\r?\n/).flatMap((block) => splitSentences(block, language));
}

// Embedded media players sometimes expose their accessibility controls through
// `innerText`, and that boilerplate lands among the reading blocks beside real
// sentences.
//
// A sentence is player UI when control phrases account for most of it, and it is
// dropped whole. A sentence that merely mentions one — an article about
// picture-in-picture — is ordinary prose and is kept exactly as the page wrote it.
//
// The distinction is the point. Deleting the phrase from inside a real sentence
// emits text the page never contained: "Apple introduced picture-in-picture on the
// iPad" became "Apple introduced on the iPad", which still reads as a sentence, so
// nothing warns the reader. Evidence Mode could never highlight it, and the panel
// claims it is extracted page text. Judging whole sentences keeps that claim true.
// Text a page repeats verbatim, many times over, is not what the page is about.
//
// Player controls arrive this way, and they arrive in the language the site is
// written in — which a fixed English phrase list cannot follow. Counting how often
// a sentence repeats needs no vocabulary at all, so it recognises a Romanian or
// Chinese player exactly as well as an English one, and it catches control text
// whose extra wording dilutes it below the phrase-coverage test.
//
// Three occurrences: prose repeats a whole sentence twice often enough to be
// innocent, and three times almost never.
//
// `toLowerCase`, not `toLocaleLowerCase`, to match Swift's locale-independent
// `lowercased()`. Turkish casing rules applied on one side only would key the two
// runtimes differently.
// A page may print the same line twice — a headline echoed in a standfirst, a
// caption repeated under a gallery. It is one thing the page said, so it is one
// thing to report, and counting it twice also inflates its own word frequencies
// and pushes it up the ranking against sentences printed once.
//
// Swift folds case with the locale-independent `lowercased()`; `toLowerCase` is
// its counterpart here.
function repeatedInterfaceText(sentences) {
  const counts = new Map();
  for (const sentence of sentences) {
    const key = sentence.toLowerCase();
    counts.set(key, (counts.get(key) || 0) + 1);
  }
  return new Set(
    [...counts].filter(([, occurrences]) => occurrences >= 3).map(([key]) => key)
  );
}

function isMediaInterfaceSentence(sentence = "") {
  const trimmed = sentence.trim();
  if (!trimmed) return false;

  // `toLowerCase`, not `toLocaleLowerCase`, for the same reason as the repetition
  // key below: in a Turkish locale "PICTURE-IN-PICTURE" folds to "pıcture-ın-pıcture"
  // and stops matching, while Swift's case-insensitive search is locale-independent.
  const lower = trimmed.toLowerCase();
  const coveredCharacters = MEDIA_INTERFACE_PHRASES.reduce(
    (total, phrase) => total + (lower.split(phrase).length - 1) * graphemeCount(phrase),
    0
  );
  return coveredCharacters * 2 > graphemeCount(trimmed);
}

// The page's readable text, with interface noise removed. Blocks stay
// newline-separated exactly as the extractor emitted them, because a block boundary
// is a sentence boundary and assessStructure reads the same shape. Neither filter
// edits a sentence: one drops a sentence when known media-control phrases cover most
// of it, the other drops any sentence the page repeats three or more times, which
// needs no vocabulary and so recognises a player in any language.
export function readableText(page) {
  const blocks = String(page.text || "").split(/\r?\n/);
  const language = page.language;
  const extracted = blocks.flatMap((block) => splitSentences(block, language));
  const repeated = repeatedInterfaceText(extracted);

  const seen = new Set();
  const kept = [];
  for (const block of blocks) {
    const sentences = splitSentences(block, language).filter((sentence) => {
      if (isMediaInterfaceSentence(sentence)) return false;
      const key = sentence.toLowerCase();
      if (repeated.has(key) || seen.has(key)) return false;
      seen.add(key);
      return true;
    });
    if (sentences.length) kept.push(sentences.join(" "));
  }
  return kept.join("\n");
}

// A section or index page stitches unrelated headlines into a confident-looking
// summary, so the interface has to know what kind of page it is looking at. Read the
// extractor's reading blocks: many blocks, few sentence endings, and almost no long
// punctuated prose describe a list of links rather than a text to summarize. Article
// stays the safe default — including the single-block extractor fallback — because
// hiding a real summary costs the reader more than summarizing a list.
// Reference sites close a paragraph with its citations — "…under real
// uncertainty.[12]" — so the block ends in a bracket and reads as unpunctuated.
// That alone scored the English Wikipedia article on artificial intelligence at
// 13.9% punctuated and classified it a listing, which hides the analysis behind
// the section-page notice. The markers are furniture, not prose, so they are
// ignored when asking whether a block ends in a sentence. The block's own text is
// never altered; only this question is asked of the trimmed form.
//
// Scanned by code point rather than matched with a regular expression: the two
// runtimes' regex dialects disagree about what \s covers, and this must not.
function withoutTrailingCitations(block) {
  const points = [...block];
  let end = points.length;
  for (;;) {
    while (end > 0 && points[end - 1] === " ") end -= 1;
    if (end === 0 || points[end - 1] !== "]") break;
    let open = end - 2;
    while (open >= 0 && points[open] !== "[" && points[open] !== "]") open -= 1;
    if (open < 0 || points[open] !== "[" || end - 1 - open > 25) break;
    end = open;
  }
  return points.slice(0, end).join("");
}

export function assessStructure(page) {
  const blocks = (page.text || "").split(/\r?\n/).map(normalizeText).filter(Boolean);
  if (blocks.length < MINIMUM_LISTING_BLOCKS) return "article";

  let punctuatedBlocks = 0;
  let totalCharacters = 0;
  let longPunctuatedCharacters = 0;
  for (const block of blocks) {
    // Graphemes, matching Swift's `count`. Measuring in UTF-16 units here put the
    // two runtimes on opposite sides of the paragraph threshold for the same block
    // — 219 characters a reader can see, 225 units — so one discounted its
    // citations and the other did not, and they disagreed about the whole page.
    const characters = graphemeCount(block);
    const longBlock = CJK_PATTERN.test(block) ? LONG_CJK_BLOCK_CHARACTERS : LONG_BLOCK_CHARACTERS;
    // Only a block already long enough to be a paragraph has its citations
    // discounted. A short teaser ending "…region. [1]" is a list entry whatever
    // the bracket holds, and stripping there would read a headline list as prose.
    const isPunctuated = BLOCK_ENDING_PATTERN.test(
      characters >= longBlock ? withoutTrailingCitations(block) : block
    );
    totalCharacters += characters;
    if (isPunctuated) punctuatedBlocks += 1;
    if (isPunctuated && characters >= longBlock) longPunctuatedCharacters += characters;
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

export function analyzePage(page) {
  return {
    risk: assessRisk(page),
    readMinutes: Math.max(1, Math.ceil((page.wordCount || 0) / 220)),
    analyzedAt: new Date().toISOString()
  };
}
