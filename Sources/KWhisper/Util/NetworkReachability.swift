import Foundation
import Network

/// System network reachability via `NWPathMonitor`. Used by the dictation pipeline
/// to fail fast when there's no internet, instead of waiting for a 12s HTTP timeout.
///
/// `NWPathMonitor` reflects the OS-level path status (Wi-Fi/Ethernet/cellular up,
/// link active) — it's not a captive-portal check, so it won't catch "connected to
/// Wi-Fi but no real internet" cases. Those still surface via the normal HTTP error
/// path with the tightened 12s timeout.
@MainActor
final class NetworkReachability {
    static let shared = NetworkReachability()

    private(set) var isOnline: Bool = true  // optimistic until the monitor reports otherwise

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "app.kwhisper.network-reachability")
    private var started = false

    private init() {}

    func start() {
        guard !started else { return }
        started = true
        monitor.pathUpdateHandler = { [weak self] path in
            let online = (path.status == .satisfied)
            Task { @MainActor in
                guard let self else { return }
                if self.isOnline != online {
                    self.isOnline = online
                    Log.app.info("network reachability changed: online=\(online)")
                }
            }
        }
        monitor.start(queue: queue)
    }
}
