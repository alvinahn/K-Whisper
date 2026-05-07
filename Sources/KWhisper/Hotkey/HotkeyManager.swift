import Foundation
import AppKit
import Combine
import Carbon.HIToolbox

/// Wires together:
///  - The Carbon-registered toggle hotkey (⌥⌘Space by default)
///  - The configurable hold/tap modifier key (Right ⌘, Right ⌥, Fn, …)
///  - Esc cancellation, registered only while a recording is active
@MainActor
final class HotkeyManager: ObservableObject {
    enum Trigger {
        case toggle                       // Carbon ⌥⌘Space
        case tap                          // quick press of hold key → toggle on/off
        case holdStart                    // hold key activated past threshold
        case holdEnd(durationMs: Int)     // hold key released after activation
        case escape                       // Esc pressed while recording active
    }

    var onTrigger: ((Trigger) -> Void)?

    private var carbon: CarbonHotkey?
    private var escHotkey: CarbonHotkey?
    private var holdMonitor: HoldKeyMonitor?
    private var holdPressTime: Date?
    private let settings = Settings.shared
    private var settingsSubs: Set<AnyCancellable> = []

    func start() {
        rebuildCarbon()
        if settings.holdKeyEnabled {
            startHoldMonitor()
        }

        // Live-reload when the user changes any hotkey-related setting.
        // @Published fires in willSet, so when our sink runs the underlying property
        // (e.g. settings.holdKey) is still the OLD value. Defer to the next runloop
        // tick so reload() reads the freshly-committed value from Settings.
        let deferReload: () -> Void = { [weak self] in
            DispatchQueue.main.async { self?.reload() }
        }
        settings.$holdKey.dropFirst().sink { _ in deferReload() }.store(in: &settingsSubs)
        settings.$holdKeyEnabled.dropFirst().sink { _ in deferReload() }.store(in: &settingsSubs)
        settings.$toggleHotkeyKeyCode.dropFirst().sink { _ in deferReload() }.store(in: &settingsSubs)
        settings.$toggleHotkeyModifiers.dropFirst().sink { _ in deferReload() }.store(in: &settingsSubs)
    }

    func reload() {
        carbon = nil
        rebuildCarbon()
        holdMonitor?.stop()
        holdMonitor = nil
        if settings.holdKeyEnabled {
            startHoldMonitor()
        }
    }

    /// Toggle Esc consumption. Recording-active state should call (true) on start, (false) on stop.
    /// While Esc is registered, other apps don't see Esc — that's the cost of consuming it globally.
    func setEscapeCaptureActive(_ active: Bool) {
        if active {
            guard escHotkey == nil else { return }
            escHotkey = CarbonHotkey(keyCode: kVK_Escape, modifiers: 0) { [weak self] in
                Task { @MainActor in self?.onTrigger?(.escape) }
            }
            Log.hotkey.info("Esc capture enabled")
        } else {
            escHotkey = nil
            Log.hotkey.info("Esc capture disabled")
        }
    }

    private func rebuildCarbon() {
        let kc = settings.toggleHotkeyKeyCode
        let mods = settings.toggleHotkeyModifiers
        carbon = CarbonHotkey(keyCode: kc, modifiers: mods) { [weak self] in
            Task { @MainActor in
                self?.onTrigger?(.toggle)
            }
        }
        Log.hotkey.info("Toggle hotkey registered (kc=\(kc), mods=\(mods))")
    }

    private func startHoldMonitor() {
        let key = settings.holdKey
        holdMonitor = HoldKeyMonitor(key: key) { [weak self] event in
            Task { @MainActor in
                guard let self else { return }
                switch event {
                case .tap:
                    self.onTrigger?(.tap)
                case .holdStart:
                    self.holdPressTime = Date()
                    self.onTrigger?(.holdStart)
                case .holdEnd:
                    let dur = Int((Date().timeIntervalSince(self.holdPressTime ?? Date())) * 1000)
                    self.onTrigger?(.holdEnd(durationMs: dur))
                    self.holdPressTime = nil
                }
            }
        }
        holdMonitor?.start()
    }
}
