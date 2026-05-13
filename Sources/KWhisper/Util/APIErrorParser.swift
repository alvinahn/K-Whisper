import Foundation

/// Turns raw HTTP error responses from STT/LLM providers into short, human-readable strings.
///
/// All major providers (OpenAI, Groq, Anthropic, Google) return JSON of the shape:
///   `{"error": {"message": "...", "type": "...", "code": "..."}}`
///
/// We extract `error.message`, prepend a friendly status-code category, and produce a
/// short two-part error: a short title and an optional actionable hint.
enum APIErrorParser {

    /// One-line error string for the HUD: "Category: message".
    static func format(status: Int, body: String) -> String {
        let category = categoryName(for: status)
        let detail = parseMessage(from: body)
        if detail.isEmpty { return category }
        return "\(category): \(detail)"
    }

    /// Returns a short actionable hint for common status codes (or nil if none).
    static func hint(status: Int) -> String? {
        switch status {
        case 400: return "Try speaking a bit longer."
        case 401: return "Check Settings → API Keys."
        case 403: return "API key lacks permission for this model."
        case 408, 504: return "Network was slow. Try again."
        case 413: return "Audio file too large."
        case 429: return "Rate limit hit — wait a moment."
        case 500..<600: return "Provider issue — try again."
        default: return nil
        }
    }

    /// Maps `URLError` (transport-level failures: offline, timeout, DNS, etc.) into
    /// a human-friendly title + hint pair. Returns nil for codes we don't want to
    /// surface as user-facing errors (e.g. `.cancelled` is a user action, not an error).
    static func urlError(_ error: URLError) -> (title: String, hint: String)? {
        switch error.code {
        case .cancelled:
            return nil  // user cancelled — handled separately, no HUD error
        case .notConnectedToInternet:
            return ("No internet connection", "Check your Wi-Fi · Esc to dismiss")
        case .networkConnectionLost:
            return ("Network connection dropped", "Try again · Esc to dismiss")
        case .timedOut:
            return ("Request timed out", "Network is slow · try again")
        case .cannotFindHost, .dnsLookupFailed:
            return ("Can't reach server (DNS)", "Check your connection · Esc to dismiss")
        case .cannotConnectToHost:
            return ("Can't reach server", "Provider may be down · try again")
        case .internationalRoamingOff, .callIsActive, .dataNotAllowed:
            return ("Network unavailable", "Check your connection · Esc to dismiss")
        case .secureConnectionFailed, .serverCertificateUntrusted,
             .serverCertificateHasBadDate, .serverCertificateHasUnknownRoot,
             .serverCertificateNotYetValid, .clientCertificateRejected,
             .clientCertificateRequired:
            return ("Secure connection failed", "TLS error · check system clock")
        default:
            return ("Network error", error.localizedDescription)
        }
    }

    // MARK: - Internals

    private static func parseMessage(from body: String) -> String {
        // Try OpenAI / Groq / Anthropic / Gemini JSON shape: {"error":{"message":"..."}}.
        if let data = body.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let error = json["error"] as? [String: Any],
           let message = error["message"] as? String {
            return String(message.prefix(140)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        // Anthropic also sometimes returns top-level `{"type":"error","error":{...}}` — covered above.
        // Fallback: return a small slice of the raw body.
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        return String(trimmed.prefix(100))
    }

    private static func categoryName(for status: Int) -> String {
        switch status {
        case 400: return "Bad request"
        case 401: return "Invalid API key"
        case 403: return "Forbidden"
        case 404: return "Endpoint not found"
        case 408: return "Request timeout"
        case 413: return "Audio too large"
        case 429: return "Rate limited"
        case 500: return "Server error"
        case 502: return "Bad gateway"
        case 503: return "Service unavailable"
        case 504: return "Gateway timeout"
        case 500..<600: return "Server error \(status)"
        case -1: return "No response"
        default: return "HTTP \(status)"
        }
    }
}
