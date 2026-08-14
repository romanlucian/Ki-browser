import Foundation

public enum SourceComparisonEngine {
    private static let generic: Set<String> = Set(
        "page source article says said also information people new use using about into than then there these this those with would could should pagina pagină sursa sursă articol spune spus informatii informații oameni despre pentru și si avec dans cette article source information personnes dit pour les des une un et de la le".split(separator: " ").map(String.init)
    )

    public static func compare(_ first: AnalyzedSource, _ second: AnalyzedSource) -> SourceComparison {
        let firstWords = importantWords(first)
        let secondWords = importantWords(second)
        let shared = firstWords.intersection(secondWords).sorted()
        let union = firstWords.union(secondWords)
        let overlap = union.isEmpty ? 0 : Int((Double(shared.count) / Double(union.count) * 100).rounded())

        return SourceComparison(
            overlapPercent: overlap,
            sharedThemes: Array(shared.prefix(8)),
            firstNumbers: importantNumbers(first),
            secondNumbers: importantNumbers(second),
            note: "Shared words show topical overlap, not factual agreement. Read both sources before deciding which claims are supported."
        )
    }

    private static func importantWords(_ source: AnalyzedSource) -> Set<String> {
        let value = "\(source.title) \(source.content.summary) \(source.content.keyPoints.joined(separator: " "))"
        return Set(LocalAnalysisEngine.tokens(value).filter { !generic.contains($0) })
    }

    private static func importantNumbers(_ source: AnalyzedSource) -> [String] {
        let value = "\(source.content.summary) \(source.content.keyPoints.joined(separator: " "))"
        let pattern = #"\b\d[\d,.]*(?:%|\s?(?:million|billion|thousand|milliard|mille|milion|miliard|mie|mii|万|亿))?\b"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return [] }
        let range = NSRange(value.startIndex..., in: value)
        var seen: Set<String> = []
        return regex.matches(in: value, range: range).compactMap { match in
            guard let swiftRange = Range(match.range, in: value) else { return nil }
            let number = String(value[swiftRange])
            return seen.insert(number).inserted ? number : nil
        }.prefix(6).map { $0 }
    }
}
