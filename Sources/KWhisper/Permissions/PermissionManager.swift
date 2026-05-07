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

    /// Resets the macOS TCC entry for our bundle's Accessibility permission, then re-prompts.
    /// This avoids the manual "click − to remove, click + to re-add" dance after each rebuild
    /// (ad-hoc signatures change per build, leaving the existing AX entry mismatched).
    ///
    /// `tccutil reset Accessibility <bundle-id>` works without admin/sudo.
    /// After reset the entry is gone from System Settings → Accessibility, the AX prompt
    /// re-adds it with the current binary's hash, and the user only needs to flip the toggle.
    func resetAccessibility() {
        let bundleId = Bundle.main.bundleIdentifier ?? "app.kwhisper"
        let task = Process()
        task.launchPath = "/usr/bin/tccutil"
        task.arguments = ["reset", "Accessibility", bundleId]
        do {
            try task.run()
            task.waitUntilExit()
            Log.app.info("tccutil reset Accessibility \(bundleId): exit=\(task.terminationStatus)")
        } catch {
            Log.app.error("tccutil failed: \(error.localizedDescription)")
        }
        // Trigger the macOS prompt so the entry is re-added with the new code signature.
        requestAccessibility()
        // Open the AX panel for the user to flip the toggle on.
        openAccessibilityPane()
        refresh()
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
