import Foundation
import AppKit
import AVFoundation
import ApplicationServices
import Combine

@MainActor
final class PermissionManager: ObservableObject {
    static let shared = PermissionManager()

    @Published var hasMicrophone: Bool = false
    @Published var hasAccessibility: Bool = false

    private var refreshTimer: Timer?

    private init() {
        refresh()
        // Permissions can change while the app is running; poll every 2s.
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    func refresh() {
        hasMicrophone = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
        hasAccessibility = AXIsProcessTrusted()
    }

    func requestMicrophone() async -> Bool {
        let granted = await AVCaptureDevice.requestAccess(for: .audio)
        await MainActor.run { self.refresh() }
        return granted
    }

    /// Triggers the Accessibility prompt. Cannot grant programmatically — user must approve in System Settings.
    func requestAccessibility() {
        let opts: [String: Any] = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        _ = AXIsProcessTrustedWithOptions(opts as CFDictionary)
    }

    func openAccessibilityPane() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    func openInputMonitoringPane() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent") {
            NSWorkspace.shared.open(url)
        }
    }

    func openMicrophonePane() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") {
            NSWorkspace.shared.open(url)
        }
    }
}
