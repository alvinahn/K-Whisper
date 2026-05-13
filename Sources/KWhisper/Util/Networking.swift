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

    /// Open a TLS connection to each provider host the user has actually configured,
    /// so the first real request lands warm. Skips hosts where no API key is present
    /// — pinging providers the user doesn't use just adds noise to their usage
    /// dashboards (and, for Groq, can count against per-minute model-list quotas).
    /// Issues a tiny GET in the background; failures are ignored.
    /// `@MainActor` because `SecretsStore` is main-actor-isolated; called from
    /// `applicationDidFinishLaunching` which already runs on the main actor.
    @MainActor
    static func prewarm() {
        let store = SecretsStore.shared
        var urls: [URL] = []
        if store.get(.groq) != nil {
            urls.append(URL(string: "https://api.groq.com/openai/v1/models")!)
        }
        if store.get(.openai) != nil {
            urls.append(URL(string: "https://api.openai.com/v1/models")!)
        }
        if store.get(.anthropic) != nil {
            // 401 is fine — TLS still warmed.
            urls.append(URL(string: "https://api.anthropic.com/v1/messages")!)
        }
        if store.get(.google) != nil {
            urls.append(URL(string: "https://generativelanguage.googleapis.com/v1beta/models")!)
        }
        for url in urls {
            var req = URLRequest(url: url)
            req.httpMethod = "GET"
            req.timeoutInterval = 5
            // Fire-and-forget; any response (incl. error) keeps the TLS connection alive.
            shared.dataTask(with: req) { _, _, _ in }.resume()
        }
    }
}
