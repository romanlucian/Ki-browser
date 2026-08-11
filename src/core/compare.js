import { tokenize } from "./analyzer.js";

const GENERIC = new Set(
  "page source article says said also more most information people new use using about into than then there these this those with would could should".split(
    " "
  )
);

function uniqueWords(source) {
  return new Set(
    tokenize(`${source.title || ""} ${(source.keyPoints || []).join(" ")} ${source.summary || ""}`).filter(
      (word) => !GENERIC.has(word)
    )
  );
}

function importantNumbers(source) {
  return [...new Set(`${source.summary || ""} ${(source.keyPoints || []).join(" ")}`.match(/\b\d[\d,.]*(?:%|\s?(?:million|billion|thousand))?\b/gi) || [])].slice(
    0,
    6
  );
}

export function compareSources(first, second) {
  const firstWords = uniqueWords(first);
  const secondWords = uniqueWords(second);
  const shared = [...firstWords].filter((word) => secondWords.has(word));
  const union = new Set([...firstWords, ...secondWords]);
  const overlap = union.size ? shared.length / union.size : 0;

  return {
    overlapPercent: Math.round(overlap * 100),
    sharedThemes: shared.slice(0, 8),
    firstNumbers: importantNumbers(first),
    secondNumbers: importantNumbers(second),
    firstPoints: (first.keyPoints || []).slice(0, 3),
    secondPoints: (second.keyPoints || []).slice(0, 3),
    note:
      "Shared words show topical overlap, not factual agreement. Read both sources before deciding which claims are supported."
  };
}
