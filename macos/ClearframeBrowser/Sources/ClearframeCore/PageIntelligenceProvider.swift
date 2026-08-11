import Foundation

public protocol PageIntelligenceProviding: Sendable {
    func analyze(page: PageSnapshot) async throws -> PageAnalysisContent
    func translate(text: String, sourceLanguage: String, targetLanguage: String) async throws -> String
}

public struct LocalPageIntelligenceProvider: PageIntelligenceProviding {
    public init() {}

    public func analyze(page: PageSnapshot) async throws -> PageAnalysisContent {
        let result = LocalAnalysisEngine.summarize(page: page)
        if result.summary.isEmpty {
            throw PageIntelligenceError.noReadableText
        }
        return result
    }

    public func translate(
        text: String,
        sourceLanguage: String,
        targetLanguage: String
    ) async throws -> String {
        if targetLanguage == "Plain English" {
            return LocalAnalysisEngine.simplifyEnglish(text)
        }
        throw PageIntelligenceError.localTranslationUnavailable
    }
}
