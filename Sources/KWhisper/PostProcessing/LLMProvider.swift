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
        case .missingKey(let k): return "\(k.displayName) API 키가 없습니다. 설정 → API 키에서 추가하세요."
        case .http(let c, let b): return "LLM 보정 — " + APIErrorParser.format(status: c, body: b)
        case .decode(let m): return "LLM 응답 해석 실패: \(m)"
        }
    }
}
