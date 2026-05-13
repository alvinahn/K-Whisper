import Foundation

/// Shared, long-lived URLSession with HTTP/2 + keep-alive.
/// Re-using one session across requests avoids TLS handshake on every dictation.
enum Networking {
    static let shared: URLSession = {
        let cfg = URLSessionConfiguration.default
        cfg.httpAdditionalHeaders = ["User-Agent": "K-Whisper/0.1 (macOS; native)"]
        cfg.httpMaximumConnectionsPerHost = 4
        cfg.requestCachePolicy = .reloadIgnoringLocalCacheData
        // Tight timeouts: dictation E2E budget is ~1s. 12s gives generous headroom
        // for slow LLM responses without making the user stare at a stuck HUD when
        // the network is dead. Pipeline also pre-checks NWPathMonitor before firing.
        cfg.timeoutIntervalForRequest = 12
        cfg.timeoutIntervalForResource = 20
        cfg.waitsForConnectivity = false
        return URLSession(configuration: cfg)
    }()

    /// Open a TLS connection to each provider host so the first real request lands warm.
    /// Issues a tiny GET in the background; failures are ignored.
    static func prewarm() {
        let urls = [
            URL(string: "https://api.groq.com/openai/v1/models")!,        // primary STT host
            URL(string: "https://api.openai.com/v1/models")!,
            URL(string: "https://api.anthropic.com/v1/messages")!,        // 401 is fine — TLS still warmed
            URL(string: "https://generativelanguage.googleapis.com/v1beta/models")!
        ]
        for url in urls {
            var req = URLRequest(url: url)
            req.httpMethod = "GET"
            req.timeoutInterval = 5
            // Fire-and-forget; any response (incl. error) keeps the TLS connection alive.
            shared.dataTask(with: req) { _, _, _ in }.resume()
        }
    }
}
