import Foundation

enum LLMProviderKind: String, CaseIterable, Codable, Identifiable {
    case groq
    case claude
    case openai
    case gemini
    case none
    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .groq:   return "Groq (Llama)"
        case .claude: return "Claude (Anthropic)"
        case .openai: return "OpenAI"
        case .gemini: return "Gemini (Google)"
        case .none:   return "없음 (원문 그대로)"
        }
    }
}

struct Mode: Codable, Identifiable, Hashable {
    var id: String
    var name: String
    var systemPrompt: String
    var provider: LLMProviderKind
    var model: String
    var temperature: Double
    var maxTokens: Int
    var isBuiltIn: Bool

    static func makeUserId() -> String {
        "user-\(UUID().uuidString.lowercased().prefix(8))"
    }
}
