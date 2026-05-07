import AppKit
import SwiftUI
import Combine

/// A floating, borderless pill window centered on the active screen.
@MainActor
final class HUDWindowController {
    static let shared = HUDWindowController()

    private var panel: NSPanel?
    private let viewModel = HUDViewModel()
    private var phaseSub: AnyCancellable?

    var model: HUDViewModel { viewModel }

    func show() {
        if panel == nil { build() }
        adjustForCurrentPhase()
        panel?.orderFrontRegardless()
    }

    func hide() {
        panel?.orderOut(nil)
    }

    private func build() {
        let hosting = NSHostingController(rootView: HUDView(model: viewModel))
        hosting.sizingOptions = [.preferredContentSize]

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 56),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.contentViewController = hosting
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = true
        self.panel = panel

        // Resize the NSPanel whenever the SwiftUI content's preferred size changes
        // (e.g. error state expands the pill).
        phaseSub = viewModel.$phase
            .removeDuplicates()
            .sink { [weak self] _ in
                DispatchQueue.main.async { self?.adjustForCurrentPhase() }
            }
    }

    private func adjustForCurrentPhase() {
        let target = preferredSize(for: viewModel.phase)
        guard let panel = panel else { return }
        if panel.frame.size != target {
            // Keep centered on screen while resizing.
            guard let screen = NSScreen.main else { return }
            let f = screen.visibleFrame
            let x = f.midX - target.width / 2
            let y = f.midY - target.height / 2
            panel.setFrame(NSRect(origin: NSPoint(x: x, y: y), size: target), display: true, animate: false)
        } else {
            positionAtCenter()
        }
    }

    private func preferredSize(for phase: HUDViewModel.Phase) -> NSSize {
        if case .error = phase { return NSSize(width: 420, height: 70) }
        return NSSize(width: 320, height: 56)
    }

    private func positionAtCenter() {
        guard let panel = panel, let screen = NSScreen.main else { return }
        let size = panel.frame.size
        let f = screen.visibleFrame
        let x = f.midX - size.width / 2
        let y = f.midY - size.height / 2
        panel.setFrame(NSRect(x: x, y: y, width: size.width, height: size.height), display: true)
    }
}

@MainActor
final class HUDViewModel: ObservableObject {
    enum Phase: Equatable {
        case idle
        case recording
        case transcribing
        case processing(modeName: String)
        case delivered
        case error(message: String, hint: String?)
    }

    @Published var phase: Phase = .idle {
        didSet { phaseDidChange() }
    }
    @Published var elapsed: TimeInterval = 0
    @Published var level: Float = 0
    @Published var modeName: String = "Default cleanup"
    @Published var language: String = ""
    @Published var recordingTrigger: DictationCoordinator.RecordingTrigger = .toggle

    private var syntheticTimer: Timer?

    /// Drive `level` with a gentle synthetic pulse during transcribing/processing phases,
    /// so the scrolling waveform keeps animating after the mic is off (matches Superwhisper).
    private func phaseDidChange() {
        switch phase {
        case .transcribing, .processing:
            startSynthetic()
        default:
            stopSynthetic()
        }
    }

    private func startSynthetic() {
        guard syntheticTimer == nil else { return }
        let start = Date()
        syntheticTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            Task { @MainActor in
                let t = Date().timeIntervalSince(start)
                let pulse = 0.18 + 0.14 * abs(sin(t * 3.0)) + 0.08 * abs(sin(t * 5.5 + 1.0))
                self?.level = Float(min(0.55, pulse))
            }
        }
    }

    private func stopSynthetic() {
        syntheticTimer?.invalidate()
        syntheticTimer = nil
    }
}
