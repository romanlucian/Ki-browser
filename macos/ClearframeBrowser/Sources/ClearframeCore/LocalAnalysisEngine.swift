import Foundation

public enum LocalAnalysisEngine {
    private static let englishStopWords = wordSet(
        "a an and are as at be been but by can could did do does for from had has have he her hers him his how i if in into is it its may might more most must my no not of on one or our ours she should so some than that the their theirs them then there these they this those to too us was we were what when where which who why will with would you your yours about after again against all am any because before being below between both during each few further here itself just many me nor now off once only other out over own same such through under until up very while"
    )
    private static let romanianStopWords = wordSet(
        "acela acea aceea acest aceasta aceste acești ale al ai așa ca care către când cea cei cele cel ce cu cum de din după este fi fost iar în între la mai nici nu o pe pentru prin sau se și sunt un una unei unui vor"
    )
    private static let frenchStopWords = wordSet(
        "alors au aux avec ce ces comme dans de des du elle en est et eux il ils je la le les leur lui ma mais me même mes moi mon ne nos notre nous on ou par pas pour qu que quelle qui sa se ses son sont sur ta te tes toi ton tu un une vos votre vous c d j l à ça était été être"
    )
    private static let chineseStopWords = wordSet("也 个 中 为 了 与 及 和 在 对 将 是 有 的 而 这 那")
    private static let fallbackStopWords = englishStopWords
        .union(romanianStopWords)
        .union(frenchStopWords)
        .union(chineseStopWords)

    private static let mediaInterfacePhrases = [
        "subtitles settings, opens subtitles settings dialog",
        "captions settings, opens captions settings dialog",
        "video player is loading",
        "audio player is loading",
        "stream type live",
        "seek to live, currently behind live",
        "playback controls",
        "playback rate",
        "picture-in-picture"
    ]

    private static let plainReplacements: [(String, String)] = [
        ("approximately", "about"),
        ("additional", "more"),
        ("commence", "start"),
        ("consequently", "so"),
        ("demonstrate", "show"),
        ("facilitate", "help"),
        ("individuals", "people"),
        ("in order to", "to"),
        ("numerous", "many"),
        ("purchase", "buy"),
        ("regarding", "about"),
        ("subsequently", "later"),
        ("utilize", "use")
    ]

    public static func summarize(page: PageSnapshot) -> PageAnalysisContent {
        let source = normalizeReadingBlocks(
            removeRepeatedMediaInterfaceText(page.text.isEmpty ? "" : page.text)
        )
        let sentences = deduplicated(splitSentences(source))

        guard !sentences.isEmpty else {
            return PageAnalysisContent(summary: "", keyPoints: [], claimsToCheck: [])
        }

        let scored = score(sentences: sentences, title: page.title, language: page.language)
        let summaryEntries = Array(scored.sorted { $0.score > $1.score }.prefix(min(3, sentences.count)))
            .sorted { $0.index < $1.index }
        let summarySentences = summaryEntries.map(\.sentence)
        let summarySet = Set(summarySentences)
        let keyPoints = scored
            .sorted { $0.score > $1.score }
            .filter { !summarySet.contains($0.sentence) }
            .prefix(4)
            .map(\.sentence)

        let claimTerms = [
            "according", "report", "study", "research", "survey", "million", "billion",
            "percent", "guarantee", "always", "never", "only", "best", "worst", "first",
            "potrivit", "raport", "studiu", "cercetare", "sondaj", "milioane", "miliarde", "procent",
            "selon", "rapport", "étude", "recherche", "sondage", "million", "milliard", "pour cent",
            "报告", "研究", "调查", "百万", "十亿", "百分之", "保证", "最佳", "首次"
        ]
        let claims = scored
            .filter { entry in
                entry.sentence.rangeOfCharacter(from: .decimalDigits) != nil ||
                claimTerms.contains { containsClaimTerm($0, in: entry.sentence) }
            }
            .sorted { $0.score > $1.score }
            .prefix(3)
            .map(\.sentence)

        return PageAnalysisContent(
            summary: summarySentences.joined(separator: " "),
            keyPoints: Array(keyPoints),
            claimsToCheck: Array(claims)
        )
    }

    public static func simplifyEnglish(_ value: String) -> String {
        var result = normalize(value)
        for (complex, plain) in plainReplacements {
            result = result.replacingOccurrences(
                of: "\\b\(NSRegularExpression.escapedPattern(for: complex))\\b",
                with: plain,
                options: [.regularExpression, .caseInsensitive]
            )
        }
        return result
    }

    public static func canSimplifyToPlainEnglish(sourceLanguage: String) -> Bool {
        let primaryLanguage = sourceLanguage.lowercased()
            .split(whereSeparator: { $0 == "-" || $0 == "_" })
            .first
        return primaryLanguage == "en"
    }

    public static func readingTime(wordCount: Int) -> Int {
        max(1, Int(ceil(Double(wordCount) / 220.0)))
    }

    public static func splitSentences(_ value: String) -> [String] {
        var sentences: [String] = []
        var current = ""
        let endings: Set<Character> = [".", "!", "?", "。", "！", "？"]

        for character in normalize(value) {
            current.append(character)
            if endings.contains(character) {
                let sentence = normalize(current)
                if isUsefulSentenceLength(sentence) {
                    sentences.append(sentence)
                }
                current = ""
            }
        }

        let remainder = normalize(current)
        if isUsefulSentenceLength(remainder) {
            sentences.append(remainder)
        }
        return sentences
    }

    public static func tokens(_ value: String, language: String = "") -> [String] {
        var result: [String] = []
        var currentWord = ""
        let selectedStopWords = stopWords(for: language)

        func appendCurrentWord() {
            guard currentWord.count >= 2, !selectedStopWords.contains(currentWord) else {
                currentWord = ""
                return
            }
            result.append(currentWord)
            currentWord = ""
        }

        for character in value.lowercased() {
            if isCJK(character) {
                appendCurrentWord()
                let token = String(character)
                if !selectedStopWords.contains(token) { result.append(token) }
            } else if character.isLetter || character.isNumber || character == "'" || character == "’" || character == "-" {
                currentWord.append(character)
            } else {
                appendCurrentWord()
            }
        }
        appendCurrentWord()
        return result
    }

    private static func normalize(_ value: String) -> String {
        value.components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    /// The browser extractor separates rendered reading blocks with newlines. Treat
    /// each block as a sentence boundary when the page omitted punctuation so that
    /// unrelated headlines and metadata are not fused into one oversized point.
    private static func normalizeReadingBlocks(_ value: String) -> String {
        let blocks = value.components(separatedBy: .newlines)
            .map(normalize)
            .filter { !$0.isEmpty }
        guard blocks.count > 1 else { return normalize(value) }

        let endings: Set<Character> = [".", "!", "?", "。", "！", "？", ":", ";"]
        return blocks.map { block in
            guard let last = block.last, !endings.contains(last) else { return block }
            return block + "."
        }.joined(separator: " ")
    }

    /// Embedded media players sometimes expose repeated accessibility controls through
    /// `innerText`. Remove that boilerplate only when a repeated control phrase proves
    /// the page extraction contains a player UI, preserving ordinary article wording.
    private static func removeRepeatedMediaInterfaceText(_ value: String) -> String {
        let controlMatchCount = mediaInterfacePhrases.reduce(0) { count, phrase in
            count + matchCount(of: phrase, in: value)
        }
        guard controlMatchCount >= 2 else { return value }

        return mediaInterfacePhrases.reduce(value) { result, phrase in
            result.replacingOccurrences(of: phrase, with: " ", options: .caseInsensitive)
        }
    }

    private static func deduplicated(_ sentences: [String]) -> [String] {
        var seen: Set<String> = []
        return sentences.filter { sentence in
            let key = sentence.lowercased()
            guard !seen.contains(key) else { return false }
            seen.insert(key)
            return true
        }
    }

    private static func matchCount(of phrase: String, in value: String) -> Int {
        var count = 0
        var searchRange = value.startIndex..<value.endIndex
        while let match = value.range(of: phrase, options: .caseInsensitive, range: searchRange) {
            count += 1
            searchRange = match.upperBound..<value.endIndex
        }
        return count
    }

    private static func containsClaimTerm(_ term: String, in sentence: String) -> Bool {
        if term.contains(where: isCJK) {
            return sentence.localizedCaseInsensitiveContains(term)
        }
        let pattern = "\\b\(NSRegularExpression.escapedPattern(for: term))\\b"
        return sentence.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
    }

    private static func isUsefulSentenceLength(_ sentence: String) -> Bool {
        let minimum = sentence.contains(where: isCJK) ? 12 : 35
        return sentence.count >= minimum && sentence.count <= 520
    }

    private static func isCJK(_ character: Character) -> Bool {
        character.unicodeScalars.contains { scalar in
            switch scalar.value {
            case 0x3400...0x4DBF, 0x4E00...0x9FFF, 0xF900...0xFAFF,
                 0x3040...0x30FF, 0xAC00...0xD7AF:
                return true
            default:
                return false
            }
        }
    }

    private static func score(sentences: [String], title: String, language: String) -> [ScoredSentence] {
        var frequencies: [String: Int] = [:]
        for word in tokens(sentences.joined(separator: " "), language: language) {
            frequencies[word, default: 0] += 1
        }
        let maxFrequency = max(frequencies.values.max() ?? 1, 1)
        let titleWords = Set(tokens(title, language: language))

        return sentences.enumerated().map { index, sentence in
            let words = tokens(sentence, language: language)
            let topicality = words.reduce(0.0) { partial, word in
                partial + Double(frequencies[word] ?? 0) / Double(maxFrequency)
            }
            let titleOverlap = Double(words.filter(titleWords.contains).count) * 0.7
            let leadBonus = index < 3 ? 0.8 - Double(index) * 0.2 : 0
            let maximumUsefulTokens = sentence.contains(where: isCJK) ? 100 : 48
            let lengthPenalty = words.count < 7 || words.count > maximumUsefulTokens ? 0.7 : 1.0
            let score = ((topicality + titleOverlap) / sqrt(Double(max(words.count, 1))) + leadBonus) * lengthPenalty
            return ScoredSentence(sentence: sentence, index: index, score: score)
        }
    }

    private struct ScoredSentence {
        let sentence: String
        let index: Int
        let score: Double
    }

    private static func wordSet(_ value: String) -> Set<String> {
        Set(value.split(separator: " ").map(String.init))
    }

    private static func stopWords(for language: String) -> Set<String> {
        let primary = language.lowercased()
            .split(whereSeparator: { $0 == "-" || $0 == "_" })
            .first
            .map(String.init)
        switch primary {
        case "en": return englishStopWords
        case "ro": return romanianStopWords
        case "fr": return frenchStopWords
        case "zh": return chineseStopWords
        default: return fallbackStopWords
        }
    }
}
