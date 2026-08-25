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

    /// Structure thresholds calibrated on live English and Romanian section fronts and
    /// articles. Simplified Chinese has no listing measurement yet; only the shorter CJK
    /// block length follows the engine's existing CJK-aware precedent.
    private static let minimumListingBlocks = 12
    private static let listingEndPunctuationPercent = 60
    private static let listingProseMassPercent = 10
    private static let longBlockCharacters = 220
    private static let longCJKBlockCharacters = 100
    /// Sentence terminators Clearframe recognises. Latin and CJK stops, plus the
    /// Devanagari danda and double danda, the Urdu full stop, and the Arabic question
    /// mark. A script whose terminator is missing here reads as one endless sentence,
    /// which also makes its pages look unpunctuated to `assessStructure`.
    private static let sentenceEndings: Set<Character> = [
        ".", "!", "?", "。", "！", "？", "।", "॥", "۔", "؟", "։"
    ]

    /// Words that take a full stop without ending a sentence, keyed by language and
    /// deliberately never merged into one set: Italian "es." abbreviates *esempio*
    /// while Spanish "es" is the verb, so an Italian entry loose in a Spanish page
    /// would swallow the boundary after "Así es." An unrecognised language gets an
    /// empty set — no joining, rather than another language's guesses. This is the
    /// same reason the stop words above are chosen by language.
    private static let sentenceAbbreviations: [String: Set<String>] = [
        "en": wordSet("mr mrs ms dr prof sr jr st vs etc inc ltd corp fig vol pp ed al approx dept jan feb mar apr jun jul aug sep sept oct nov dec e.g i.e u.s u.k"),
        "ro": wordSet("dl dna dr ing nr ex etc pag vol art"),
        "fr": wordSet("m mme mlle dr pr st ste av ex etc vol pp"),
        "es": wordSet("sr sra srta dr dra prof ud uds etc núm pág vol"),
        "de": wordSet("hr dr prof bzw ca evtl ggf inkl usw vgl nr abs z u d"),
        "it": wordSet("sig dott dr prof avv ecc pag vol num es")
    ]

    private static let blockEndings: Set<Character> = [
        ".", "!", "?", "…", "。", "！", "？", ":", ";", "।", "॥", "۔", "؟"
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
        let source = page.text.isEmpty ? "" : page.text
        let extracted = sentencesFromReadingBlocks(source, language: page.language)
        let repeated = repeatedInterfaceText(in: extracted)
        let sentences = deduplicated(extracted)
            .filter { !isMediaInterfaceSentence($0) && !repeated.contains($0.lowercased()) }

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
        // A claim repeated from the gist or a key point gives the reader nothing new to
        // check, so keep claims to sentences the rest of the result did not already show.
        let presentedSentences = summarySet.union(keyPoints)
        let claims = scored
            .filter { entry in
                guard !presentedSentences.contains(entry.sentence) else { return false }
                return entry.sentence.rangeOfCharacter(from: .decimalDigits) != nil ||
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

    /// A section or index page stitches unrelated headlines into a confident-looking
    /// summary, so the interface has to know what kind of page it is looking at. Read
    /// the extractor's reading blocks: many blocks, few sentence endings, and almost no
    /// long punctuated prose describe a list of links rather than a text to summarize.
    /// Article stays the safe default — including the single-block extractor fallback —
    /// because hiding a real summary costs the reader more than summarizing a list.
    public static func assessStructure(page: PageSnapshot) -> PageStructure {
        let blocks = page.text.components(separatedBy: .newlines)
            .map(normalize)
            .filter { !$0.isEmpty }
        guard blocks.count >= minimumListingBlocks else { return .article }

        var punctuatedBlocks = 0
        var totalCharacters = 0
        var longPunctuatedCharacters = 0
        for block in blocks {
            let characters = block.count
            let longBlock = block.contains(where: isCJK) ? longCJKBlockCharacters : longBlockCharacters
            // Only a block already long enough to be a paragraph has its citations
            // discounted. A short teaser ending "…region. [1]" is a list entry
            // whatever the bracket holds, and stripping there would read a headline
            // list as prose.
            let considered = characters >= longBlock ? withoutTrailingCitations(block) : block
            let isPunctuated = considered.last.map(blockEndings.contains) ?? false
            totalCharacters += characters
            if isPunctuated { punctuatedBlocks += 1 }
            if isPunctuated && characters >= longBlock { longPunctuatedCharacters += characters }
        }

        // Compare the two shares as integers so both runtimes agree on the boundaries.
        let mostlyUnpunctuated = punctuatedBlocks * 100 < blocks.count * listingEndPunctuationPercent
        let littleProseMass = longPunctuatedCharacters * 100 < totalCharacters * listingProseMassPercent
        return mostlyUnpunctuated && littleProseMass ? .listing : .article
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

    public static func splitSentences(_ value: String, language: String = "") -> [String] {
        var sentences: [String] = []
        var current = ""
        let characters = Array(normalize(value))
        let abbreviations = abbreviations(for: language)

        for (index, character) in characters.enumerated() {
            current.append(character)
            if sentenceEndings.contains(character) {
                // "2.7" is a single number, not the end of one sentence and the start
                // of another. Only a period between two digits is ambiguous this way.
                if character == ".",
                   index > 0,
                   index + 1 < characters.count,
                   characters[index - 1].isNumber,
                   characters[index + 1].isNumber {
                    continue
                }
                if character == ".",
                   !periodEndsSentence(current, characters, index, abbreviations) {
                    continue
                }
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
            // Unicode scalars, not `Character`s. A `Character` is a whole grapheme
            // cluster, so a Devanagari word written with a vowel sign — "\u{092E}\u{0947}\u{0902}"
            // is one cluster and three scalars — counted as a single character here
            // and was dropped by this minimum, while the other runtime kept it.
            // Common Hindi words went missing from scoring: 8,404 tokens there
            // against 6,543 here on the same article.
            guard currentWord.unicodeScalars.count >= 2,
                  !selectedStopWords.contains(currentWord) else {
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

    /// Exactly the characters JavaScript's `\s` matches, and deliberately not
    /// `CharacterSet.whitespacesAndNewlines`.
    ///
    /// The extractor that produces `page.text` is JavaScript, and its `clean()`
    /// decides which characters survive into the text a key point has to be found
    /// in. Foundation's set disagrees on three. It counts U+200B and U+0085 as
    /// space where JavaScript does not, so this engine replaced a zero-width space
    /// the page still contains with an ordinary one and emitted "Local businesses"
    /// for a page that says "Local\u{200B}businesses" — a key point Evidence Mode
    /// can never find, under a label promising extracted page text. And it does not
    /// count U+FEFF where JavaScript does, so a byte-order mark ended a block in one
    /// runtime and not the other.
    private static let javaScriptWhitespace: CharacterSet = {
        var set = CharacterSet(charactersIn: "\t\n\u{000B}\u{000C}\r \u{00A0}\u{1680}\u{2028}\u{2029}\u{202F}\u{205F}\u{3000}\u{FEFF}")
        set.insert(charactersIn: Unicode.Scalar(0x2000)!...Unicode.Scalar(0x200A)!)
        return set
    }()

    private static func normalize(_ value: String) -> String {
        value.components(separatedBy: javaScriptWhitespace)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    /// The browser extractor separates rendered reading blocks with newlines, and a
    /// block boundary is a sentence boundary. Splitting per block keeps unrelated
    /// headlines from fusing into one oversized point without inventing terminal
    /// punctuation — an invented character would leave the sentence unfindable on the
    /// live page, which is exactly what Evidence Mode searches for.
    private static func sentencesFromReadingBlocks(_ value: String, language: String = "") -> [String] {
        // `/\r?\n/` in the other runtime: a lone carriage return, U+0085, U+2028 and
        // U+2029 are not block separators there, and `.newlines` would make them
        // separators here. They are ordinary whitespace inside a block instead.
        value
            .replacingOccurrences(of: "\r\n", with: "\n")
            .components(separatedBy: "\n")
            .flatMap { splitSentences($0, language: language) }
    }

    /// Embedded media players sometimes expose their accessibility controls through
    /// `innerText`, and that boilerplate lands among the reading blocks beside real
    /// sentences.
    ///
    /// A sentence is player UI when control phrases account for most of it, and it is
    /// dropped whole. A sentence that merely mentions one — an article about
    /// picture-in-picture — is ordinary prose and is kept exactly as the page wrote it.
    ///
    /// The distinction is the point. Deleting the phrase from inside a real sentence
    /// emits text the page never contained: "Apple introduced picture-in-picture on the
    /// iPad" became "Apple introduced on the iPad", which still reads as a sentence, so
    /// nothing warns the reader. Evidence Mode could never highlight it, and the panel
    /// claims it is extracted page text. Judging whole sentences keeps that claim true.
    /// Text a page repeats verbatim, many times over, is not what the page is about.
    ///
    /// Player controls arrive this way, and they arrive in the language the site is
    /// written in — which a fixed English phrase list cannot follow. Counting how
    /// often a sentence repeats needs no vocabulary at all, so it recognises a
    /// Romanian or Chinese player exactly as well as an English one, and it catches
    /// control text whose extra wording dilutes it below the phrase-coverage test.
    ///
    /// Three occurrences: prose repeats a whole sentence twice often enough to be
    /// innocent, and three times almost never.
    private static func repeatedInterfaceText(in sentences: [String]) -> Set<String> {
        var counts: [String: Int] = [:]
        for sentence in sentences {
            counts[sentence.lowercased(), default: 0] += 1
        }
        return Set(counts.filter { $0.value >= 3 }.keys)
    }

    private static func isMediaInterfaceSentence(_ sentence: String) -> Bool {
        let trimmed = sentence.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }

        // `count` is a count of `Character`s — extended grapheme clusters. The
        // JavaScript runtime segments graphemes to match it, because its native
        // `.length` counts UTF-16 units and would measure the same decomposed
        // sentence as longer, putting the two runtimes on opposite sides of the
        // half-way test. Every phrase here is ASCII; a non-ASCII one would need
        // checking too, since Swift matches across normalisation forms and
        // JavaScript's `split` does not.
        let coveredCharacters = mediaInterfacePhrases.reduce(0) { total, phrase in
            total + matchCount(of: phrase, in: trimmed) * phrase.count
        }
        return coveredCharacters * 2 > trimmed.count
    }

    private static func abbreviations(for language: String) -> Set<String> {
        let primary = language
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .split(whereSeparator: { $0 == "-" || $0 == "_" })
            .first
            .map(String.init) ?? ""
        return sentenceAbbreviations[primary] ?? []
    }

    /// The word a period follows, so "(e.g." asks about "e.g" and "Dr." about "dr".
    ///
    /// The last space is found among unicode scalars rather than `Character`s. A
    /// combining mark following a space forms one grapheme cluster with it, which
    /// is not equal to `" "`, so splitting on Characters would run straight past
    /// the separator that JavaScript's `lastIndexOf(" ")` stops at.
    private static func trailingWord(_ value: String) -> String {
        let scalars = Array(String(value.dropLast()).unicodeScalars)
        var start = scalars.count
        while start > 0, scalars[start - 1] != " " { start -= 1 }
        let word = String(String.UnicodeScalarView(scalars[start...]))
        return String(word.drop { !$0.isLetter && !$0.isNumber }).lowercased()
    }

    private static func periodEndsSentence(
        _ current: String,
        _ characters: [Character],
        _ index: Int,
        _ abbreviations: Set<String>
    ) -> Bool {
        var next = index + 1
        while next < characters.count, characters[next] == " " { next += 1 }
        guard next < characters.count else { return true }

        let following = characters[next]
        // "e.g. scheduling", "U.S. policy", "approx. 15" — nothing starts a sentence
        // with a lowercase letter or a digit, so that stop belonged to the word.
        if following.isLowercase || following.isNumber { return false }

        let word = trailingWord(current)
        // "U.S. policy", "J. R. R. Tolkien" — a lone letter before a stop is an
        // initial, not the end of a thought.
        if word.count == 1, word.first?.isLetter == true { return false }
        // A capital follows, so only a known abbreviation joins them: "Dr. Alison" is
        // one sentence and "the office. Analysts" is two.
        return !abbreviations.contains(word)
    }

    /// Reference sites close a paragraph with its citations — "…under real
    /// uncertainty.[12]" — so the block ends in a bracket and reads as
    /// unpunctuated. That alone scored the English Wikipedia article on artificial
    /// intelligence at 13.9% punctuated and classified it a listing, which hides the
    /// analysis behind the section-page notice. The markers are furniture, not
    /// prose, so they are ignored when asking whether a block ends in a sentence.
    /// The block's own text is never altered; only this question is asked of the
    /// trimmed form.
    ///
    /// Scanned by unicode scalar rather than matched with a regular expression: the
    /// two runtimes' regex dialects disagree about what `\s` covers, and this must
    /// not.
    private static func withoutTrailingCitations(_ block: String) -> String {
        let scalars = Array(block.unicodeScalars)
        var end = scalars.count
        while true {
            while end > 0, scalars[end - 1] == " " { end -= 1 }
            guard end > 0, scalars[end - 1] == "]" else { break }
            var open = end - 2
            while open >= 0, scalars[open] != "[", scalars[open] != "]" { open -= 1 }
            guard open >= 0, scalars[open] == "[", end - 1 - open <= 25 else { break }
            end = open
        }
        return String(String.UnicodeScalarView(scalars[..<end]))
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
            // The same list as `CJK_PATTERN` in the other runtime, which cannot use
            // `\p{Script=...}` here because Swift exposes no script property. This
            // decides the shortest sentence worth keeping and the size a block must
            // reach to count as a paragraph, so a character one runtime calls CJK
            // and the other does not gives two answers about the same page. The
            // ranges beyond the Basic Multilingual Plane and the halfwidth katakana
            // were missing, and `\p{Script=Han}` and `\p{Script=Katakana}` include
            // both.
            case 0x1100...0x11FF,      // Hangul Jamo
                 0x2E80...0x2EFF,      // CJK Radicals Supplement
                 0x2F00...0x2FDF,      // Kangxi Radicals
                 0x3005, 0x3007,       // iteration mark, ideographic zero
                 0x3040...0x30FF,      // Hiragana and Katakana
                 0x3130...0x318F,      // Hangul Compatibility Jamo
                 0x31F0...0x31FF,      // Katakana Phonetic Extensions
                 0x3400...0x4DBF,      // CJK Extension A
                 0x4E00...0x9FFF,      // CJK Unified Ideographs
                 0xA960...0xA97F,      // Hangul Jamo Extended-A
                 0xAC00...0xD7AF,      // Hangul Syllables
                 0xD7B0...0xD7FF,      // Hangul Jamo Extended-B
                 0xF900...0xFAFF,      // CJK Compatibility Ideographs
                 0xFF66...0xFF9F,      // halfwidth Katakana
                 0x20000...0x3134F,    // CJK Extensions B through G
                 0x2F800...0x2FA1F:    // CJK Compatibility Supplement
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
