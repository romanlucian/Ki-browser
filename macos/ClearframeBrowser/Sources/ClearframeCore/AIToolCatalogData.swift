import Foundation

/// The maintainable, compile-time catalog configuration. Updates are reviewed,
/// tested, and shipped with the app; this file is never replaced by remote code.
enum AIToolCatalogData {
    static let tools: [AIToolListing] = [
        tool(
            "chatgpt", "ChatGPT", "OpenAI", "GPT", "General AI assistant",
            "General questions, brainstorming, coding, and conversational image work.",
            [.askAndLearn, .write, .research, .createImages, .code],
            "https://chatgpt.com/",
            recommendations: [
                recommendation(
                    .askAndLearn, .bestOverall,
                    "A broad starting point for everyday questions, learning, writing, images, and code.",
                    "https://help.openai.com/en/articles/12677804-what-is-chatgpt-faq"
                )
            ]
        ),
        tool(
            "claude", "Claude", "Anthropic", "CL", "Thoughtful AI assistant",
            "Long documents, careful writing, structured reasoning, and code explanation.",
            [.askAndLearn, .write, .code],
            "https://claude.ai/",
            recommendations: [
                recommendation(
                    .write, .bestOverall,
                    "A focused choice for drafting, revising, and working through long written material.",
                    "https://www.anthropic.com/claude"
                )
            ]
        ),
        tool(
            "gemini", "Gemini", "Google", "GE", "Multimodal AI assistant",
            "Multimodal questions, research, coding, and Google image creation or editing with Nano Banana where available.",
            [.askAndLearn, .research, .createImages, .code],
            "https://gemini.google.com/"
        ),
        tool(
            "mistral", "Le Chat", "Mistral AI", "MI", "Multilingual AI assistant",
            "Multilingual chat, drafting, translation, and coding assistance.",
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
            "https://chat.deepseek.com/",
            recommendations: [
                recommendation(
                    .code, .bestValue,
                    "A code-focused web entry point that can be tried before deciding whether a paid plan is useful.",
                    "https://www.deepseek.com/"
                )
            ]
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
            "https://www.perplexity.ai/",
            recommendations: [
                recommendation(
                    .research, .bestOverall,
                    "A research-first interface that puts web sources alongside its answers.",
                    "https://www.perplexity.ai/help-center/en/articles/10352901-what-is-perplexity"
                )
            ]
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
            access: .providerTerms
        ),
        tool(
            "midjourney", "Midjourney", "Midjourney", "MJ", "Visual creation studio",
            "Visual style exploration and high-concept image ideation.",
            [.createImages],
            "https://www.midjourney.com/",
            access: .paidPlan
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
            access: .providerTerms
        ),
        tool(
            "canva", "Canva", "Canva", "CA", "Visual design workspace",
            "Template-led social graphics and approachable video creation and editing.",
            [.createImages, .createVideos],
            "https://www.canva.com/",
            recommendations: [
                recommendation(
                    .createVideos, .easiestToStart,
                    "A template-led path for people who want to assemble and edit a video visually.",
                    "https://www.canva.com/video-editor/"
                )
            ]
        ),
        tool(
            "deepl", "DeepL", "DeepL", "DL", "Translation and writing",
            "Focused text and document translation plus multilingual rewriting.",
            [.translate],
            "https://www.deepl.com/translator",
            recommendations: [
                recommendation(
                    .translate, .bestOverall,
                    "A dedicated text and document translation interface rather than a general chat tool.",
                    "https://www.deepl.com/en/features/document-translation"
                )
            ]
        ),
        tool(
            "google-translate", "Google Translate", "Google", "GT", "Translation utility",
            "Quick phrase, document, and broad-language translation.",
            [.translate],
            "https://translate.google.com/"
        )
    ]

    private static func tool(
        _ id: String,
        _ name: String,
        _ maker: String,
        _ monogram: String,
        _ kind: String,
        _ bestFor: String,
        _ categories: [AIToolCategory],
        _ url: String,
        access: AIToolAccessLabel = .freeToTry,
        recommendations: [AIToolRecommendation] = []
    ) -> AIToolListing {
        AIToolListing(
            id: id,
            name: name,
            maker: maker,
            monogram: monogram,
            kind: kind,
            bestFor: bestFor,
            access: access,
            officialURL: URL(string: url)!,
            categories: categories,
            recommendations: recommendations
        )
    }

    private static func recommendation(
        _ category: AIToolCategory,
        _ badge: AIToolRecommendationBadge,
        _ rationale: String,
        _ officialSourceURL: String
    ) -> AIToolRecommendation {
        AIToolRecommendation(
            category: category,
            badge: badge,
            rationale: rationale,
            officialSourceURL: URL(string: officialSourceURL)!
        )
    }
}
