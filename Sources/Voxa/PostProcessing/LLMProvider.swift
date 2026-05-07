import Foundation

protocol LLMProvider {
    func process(transcript: String, mode: Mode, system: String, user: String) async throws -> String
}

enum LLMError: Error, LocalizedError {
    case missingKey(LLMProviderKind)
    case http(Int, String)
    case decode(String)
    var errorDescription: String? {
        switch self {
        case .missingKey(let k): return "\(k.displayName) API key missing. Add it in Settings → API Keys."
        case .http(let c, let b): return "LLM API error (\(c)): \(b)"
        case .decode(let m): return "LLM response decode failed: \(m)"
        }
    }
}
