import Foundation

public enum AIToolCategory: String, CaseIterable, Codable, Identifiable, Sendable {
    case askAndLearn = "Ask & Learn"
    case write = "Write"
    case research = "Research"
    case createImages = "Create Images"
    case createVideos = "Create Videos"
    case translate = "Translate"
    case code = "Code"

    public var id: String { rawValue }

    public var symbolName: String {
        switch self {
        case .askAndLearn: return "lightbulb.max"
        case .write: return "text.badge.plus"
        case .research: return "books.vertical"
        case .createImages: return "photo.on.rectangle.angled"
        case .createVideos: return "film.stack"
        case .translate: return "character.book.closed"
        case .code: return "chevron.left.forwardslash.chevron.right"
        }
    }
}

public struct AIToolListing: Identifiable, Equatable, Sendable {
    public let id: String
    public let name: String
    public let maker: String
    public let monogram: String
    public let kind: String
    public let bestFor: String
    public let accessHint: String
    public let officialURL: URL
    public let categories: [AIToolCategory]

    public init(
        id: String,
        name: String,
        maker: String,
        monogram: String,
        kind: String,
        bestFor: String,
        accessHint: String,
        officialURL: URL,
        categories: [AIToolCategory]
    ) {
        self.id = id
        self.name = name
        self.maker = maker
        self.monogram = monogram
        self.kind = kind
        self.bestFor = bestFor
        self.accessHint = accessHint
        self.officialURL = officialURL
        self.categories = categories
    }
}

public enum AIToolCatalog {
    /// A small, static editorial catalog. Order is intentional but is not a
    /// live ranking, performance benchmark, or commercial placement.
    public static let tools: [AIToolListing] = [
        tool(
            "chatgpt", "ChatGPT", "OpenAI", "GPT", "General AI assistant",
            "General questions, brainstorming, coding, and conversational image work.",
            [.askAndLearn, .write, .research, .createImages, .code],
            "https://chatgpt.com/"
        ),
        tool(
            "claude", "Claude", "Anthropic", "CL", "Thoughtful AI assistant",
            "Long documents, careful writing, structured reasoning, and code explanation.",
            [.askAndLearn, .write, .code],
            "https://claude.ai/"
        ),
        tool(
            "gemini", "Gemini", "Google", "GE", "Multimodal AI assistant",
            "Multimodal questions, research, coding, and Google image creation or editing with Nano Banana where available.",
            [.askAndLearn, .research, .createImages, .code],
            "https://gemini.google.com/"
        ),
        tool(
            "mistral", "Le Chat", "Mistral AI", "MI", "Multilingual AI assistant",
            "Fast multilingual chat, drafting, translation, and coding assistance.",
            [.askAndLearn, .write, .translate],
            "https://chat.mistral.ai/chat"
        ),
        tool(
            "grok", "Grok", "xAI", "GR", "Conversational AI assistant",
            "Conversational exploration with a more informal style; verify important claims.",
            [.askAndLearn],
            "https://grok.com/"
        ),
        tool(
            "deepseek", "DeepSeek", "DeepSeek", "DS", "Reasoning and code assistant",
            "Technical reasoning, research exploration, and code-oriented problem solving.",
            [.research, .code],
            "https://chat.deepseek.com/"
        ),
        tool(
            "qwen", "Qwen", "Alibaba Cloud", "QW", "Multilingual creative assistant",
            "Multilingual translation, coding, and image experimentation in one interface.",
            [.createImages, .translate, .code],
            "https://chat.qwen.ai/"
        ),
        tool(
            "kimi", "Kimi", "Moonshot AI", "KI", "Knowledge-work assistant",
            "Long reading, research organization, and knowledge-work drafts.",
            [.write, .research],
            "https://www.kimi.com/"
        ),
        tool(
            "perplexity", "Perplexity", "Perplexity AI", "PX", "AI research search",
            "Starting web research with visible source links; still check primary sources.",
            [.research],
            "https://www.perplexity.ai/"
        ),
        tool(
            "firefly", "Adobe Firefly", "Adobe", "FF", "Creative AI studio",
            "Design-oriented image and video generation within Adobe creative workflows.",
            [.createImages, .createVideos],
            "https://firefly.adobe.com/"
        ),
        tool(
            "veo", "Veo", "Google DeepMind", "VE", "Video generation",
            "Creating and refining video ideas in Google Flow; access and features depend on Google.",
            [.createVideos],
            "https://labs.google/fx/tools/flow",
            access: "Availability controlled by Google"
        ),
        tool(
            "midjourney", "Midjourney", "Midjourney", "MJ", "Visual creation studio",
            "Visual style exploration and high-concept image ideation.",
            [.createImages],
            "https://www.midjourney.com/",
            access: "Paid access may be required"
        ),
        tool(
            "runway", "Runway", "Runway AI", "RW", "AI video studio",
            "Generating and editing video with prompt-driven creative tools.",
            [.createVideos],
            "https://app.runwayml.com/"
        ),
        tool(
            "seedance", "Seedance", "ByteDance Seed", "SE", "Video generation model",
            "Text- or image-guided multi-shot video concepts from ByteDance Seed.",
            [.createVideos],
            "https://seed.bytedance.com/en/seedance",
            access: "Availability controlled by ByteDance"
        ),
        tool(
            "canva", "Canva", "Canva", "CA", "Visual design workspace",
            "Template-led social graphics and approachable video creation and editing.",
            [.createImages, .createVideos],
            "https://www.canva.com/"
        ),
        tool(
            "deepl", "DeepL", "DeepL", "DL", "Translation and writing",
            "Focused text and document translation plus multilingual rewriting.",
            [.translate],
            "https://www.deepl.com/translator"
        ),
        tool(
            "google-translate", "Google Translate", "Google", "GT", "Translation utility",
            "Quick phrase, document, and broad-language translation.",
            [.translate],
            "https://translate.google.com/",
            access: "Open web tool; terms may change"
        )
    ]

    public static func filtered(
        category: AIToolCategory?,
        query rawQuery: String
    ) -> [AIToolListing] {
        let query = rawQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return tools.filter { tool in
            let isInCategory = category.map { tool.categories.contains($0) } ?? true
            guard isInCategory else { return false }
            guard !query.isEmpty else { return true }
            let searchable = [
                tool.name,
                tool.maker,
                tool.kind,
                tool.bestFor,
                tool.categories.map(\.rawValue).joined(separator: " ")
            ].joined(separator: " ").lowercased()
            return query.split(whereSeparator: \.isWhitespace).allSatisfy { searchable.contains($0) }
        }
    }

    private static func tool(
        _ id: String,
        _ name: String,
        _ maker: String,
        _ monogram: String,
        _ kind: String,
        _ bestFor: String,
        _ categories: [AIToolCategory],
        _ url: String,
        access: String = "Free access may be available"
    ) -> AIToolListing {
        AIToolListing(
            id: id,
            name: name,
            maker: maker,
            monogram: monogram,
            kind: kind,
            bestFor: bestFor,
            accessHint: access,
            officialURL: URL(string: url)!,
            categories: categories
        )
    }
}
