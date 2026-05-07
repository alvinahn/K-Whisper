import AppKit
import SwiftUI

/// A floating, borderless pill window pinned near the top of the screen.
@MainActor
final class HUDWindowController {
    static let shared = HUDWindowController()

    private var panel: NSPanel?
    private let viewModel = HUDViewModel()

    var model: HUDViewModel { viewModel }

    func show() {
        if panel == nil { build() }
        positionAtTop()
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
    }

    private func positionAtTop() {
        guard let panel = panel, let screen = NSScreen.main else { return }
        let size = panel.frame.size
        let f = screen.visibleFrame
        let x = f.midX - size.width / 2
        let y = f.maxY - size.height - 12
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
        case error(String)
    }

    @Published var phase: Phase = .idle
    @Published var elapsed: TimeInterval = 0
    @Published var level: Float = 0
    @Published var modeName: String = "Default cleanup"
    @Published var language: String = ""
}
