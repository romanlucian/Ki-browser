import Foundation

public enum LocalAnalysisEngine {
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

    /// The page's readable text, with interface noise removed.
    ///
    /// Blocks stay newline-separated exactly as the extractor emitted them, because
    /// a block boundary is a sentence boundary and `assessStructure` reads the same
    /// shape. Two filters run over it and neither edits a sentence: one drops a
    /// sentence when known media-control phrases cover most of it, the other drops
    /// any sentence the page repeats three or more times, which needs no vocabulary
    /// and so recognises a player in any language. `zf.ro` is the standing
    /// regression case for both, and an earlier version that deleted those phrases
    /// from inside ordinary prose emitted text the page did not contain — never
    /// reintroduce editing in place.
    public static func readableText(page: PageSnapshot) -> String {
        let blocks = page.text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .components(separatedBy: "\n")
        let language = page.language
        let extracted = blocks.flatMap { splitSentences($0, language: language) }
        let repeated = repeatedInterfaceText(in: extracted)

        var seen: Set<String> = []
        var kept: [String] = []
        for block in blocks {
            let sentences = splitSentences(block, language: language).filter { sentence in
                guard !isMediaInterfaceSentence(sentence) else { return false }
                let key = sentence.lowercased()
                guard !repeated.contains(key) else { return false }
                return seen.insert(key).inserted
            }
            guard !sentences.isEmpty else { continue }
            kept.append(sentences.joined(separator: " "))
        }
        return kept.joined(separator: "\n")
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

    /// How many words a piece of extracted text holds.
    ///
    /// The same rule the extractor applies to the whole page: CJK and Hangul count
    /// one word per character, because those scripts write no spaces; everything
    /// else counts a run of letters, marks and digits as one. Kept here so the
    /// number shown beside text about to leave the Mac is a count of that text, not
    /// of the page it came from.
    public static func wordCount(of value: String) -> Int {
        var count = 0
        var inWord = false
        for scalar in value.unicodeScalars {
            if isSingleCharacterWord(scalar) {
                count += 1
                inWord = false
            } else if isWordScalar(scalar) {
                if !inWord { count += 1 }
                inWord = true
            } else {
                inWord = false
            }
        }
        return count
    }

    private static func isSingleCharacterWord(_ scalar: Unicode.Scalar) -> Bool {
        let properties = scalar.properties
        return properties.isIdeographic || (0x3040...0x30FF).contains(scalar.value)
            || (0xAC00...0xD7AF).contains(scalar.value) || (0x1100...0x11FF).contains(scalar.value)
    }

    private static func isWordScalar(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.properties.generalCategory {
        case .uppercaseLetter, .lowercaseLetter, .titlecaseLetter, .modifierLetter, .otherLetter,
             .nonspacingMark, .spacingMark, .enclosingMark,
             .decimalNumber, .letterNumber, .otherNumber:
            return true
        default:
            return false
        }
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

    private static func matchCount(of phrase: String, in value: String) -> Int {
        var count = 0
        var searchRange = value.startIndex..<value.endIndex
        while let match = value.range(of: phrase, options: .caseInsensitive, range: searchRange) {
            count += 1
            searchRange = match.upperBound..<value.endIndex
        }
        return count
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

    private static func wordSet(_ value: String) -> Set<String> {
        Set(value.split(separator: " ").map(String.init))
    }

}
