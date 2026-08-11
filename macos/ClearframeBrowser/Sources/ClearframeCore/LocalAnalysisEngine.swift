import Foundation

public enum LocalAnalysisEngine {
    private static let stopWords: Set<String> = Set(
        "a an and are as at be been but by can could did do does for from had has have he her hers him his how i if in into is it its may might more most must my no not of on one or our ours she should so some than that the their theirs them then there these they this those to too us was we were what when where which who why will with would you your yours about after again against all am any because before being below between both during each few further here itself just many me nor now off once only other out over own same such through under until up very while".split(separator: " ").map(String.init)
    )

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
        let source = normalize(page.text.isEmpty ? "" : page.text)
        let sentences = splitSentences(source)

        guard !sentences.isEmpty else {
            return PageAnalysisContent(summary: "", keyPoints: [], claimsToCheck: [])
        }

        let scored = score(sentences: sentences, title: page.title)
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
            "percent", "guarantee", "always", "never", "only", "best", "worst", "first"
        ]
        let claims = scored
            .filter { entry in
                entry.sentence.rangeOfCharacter(from: .decimalDigits) != nil ||
                claimTerms.contains { entry.sentence.localizedCaseInsensitiveContains($0) }
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

    public static func readingTime(wordCount: Int) -> Int {
        max(1, Int((Double(wordCount) / 220.0).rounded()))
    }

    public static func splitSentences(_ value: String) -> [String] {
        var sentences: [String] = []
        var current = ""
        let endings: Set<Character> = [".", "!", "?", "。", "！", "？"]

        for character in normalize(value) {
            current.append(character)
            if endings.contains(character) {
                let sentence = normalize(current)
                if sentence.count >= 35 && sentence.count <= 520 {
                    sentences.append(sentence)
                }
                current = ""
            }
        }

        let remainder = normalize(current)
        if remainder.count >= 35 && remainder.count <= 520 {
            sentences.append(remainder)
        }
        return sentences
    }

    public static func tokens(_ value: String) -> [String] {
        value.lowercased()
            .split { !$0.isLetter && !$0.isNumber && $0 != "'" && $0 != "’" && $0 != "-" }
            .map(String.init)
            .filter { $0.count >= 3 && !stopWords.contains($0) }
    }

    private static func normalize(_ value: String) -> String {
        value.components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    private static func score(sentences: [String], title: String) -> [ScoredSentence] {
        var frequencies: [String: Int] = [:]
        for word in tokens(sentences.joined(separator: " ")) {
            frequencies[word, default: 0] += 1
        }
        let maxFrequency = max(frequencies.values.max() ?? 1, 1)
        let titleWords = Set(tokens(title))

        return sentences.enumerated().map { index, sentence in
            let words = tokens(sentence)
            let topicality = words.reduce(0.0) { partial, word in
                partial + Double(frequencies[word] ?? 0) / Double(maxFrequency)
            }
            let titleOverlap = Double(words.filter(titleWords.contains).count) * 0.7
            let leadBonus = index < 3 ? 0.8 - Double(index) * 0.2 : 0
            let lengthPenalty = words.count < 7 || words.count > 48 ? 0.7 : 1.0
            let score = ((topicality + titleOverlap) / sqrt(Double(max(words.count, 1))) + leadBonus) * lengthPenalty
            return ScoredSentence(sentence: sentence, index: index, score: score)
        }
    }

    private struct ScoredSentence {
        let sentence: String
        let index: Int
        let score: Double
    }
}
