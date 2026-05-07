import Foundation
import AppKit
import Combine

/// Combines toggle hotkey (⌥⌘Space) and a configurable hold-to-talk modifier key.
@MainActor
final class HotkeyManager: ObservableObject {
    enum Trigger {
        case toggle
        case holdStart
        case holdEnd(durationMs: Int)
    }

    var onTrigger: ((Trigger) -> Void)?

    private var carbon: CarbonHotkey?
    private var holdMonitor: HoldKeyMonitor?
    private var holdPressTime: Date?
    private let settings = Settings.shared

    func start() {
        rebuildCarbon()
        if settings.holdKeyEnabled {
            startHoldMonitor()
        }
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
        holdMonitor = HoldKeyMonitor(key: key) { [weak self] pressed in
            Task { @MainActor in
                guard let self else { return }
                if pressed {
                    self.holdPressTime = Date()
                    self.onTrigger?(.holdStart)
                } else {
                    let dur = Int((Date().timeIntervalSince(self.holdPressTime ?? Date())) * 1000)
                    self.onTrigger?(.holdEnd(durationMs: dur))
                    self.holdPressTime = nil
                }
            }
        }
        holdMonitor?.start()
    }
}
