import Foundation
import AppKit

/// Specific physical key used for push-to-talk. Detected via NSEvent flag-change monitoring,
/// which does NOT require Input Monitoring permission.
enum HoldKey: String, CaseIterable, Codable, Identifiable {
    case rightOption
    case rightCommand
    case rightShift
    case rightControl
    case fn

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .rightOption:  return "Right ⌥ Option (recommended)"
        case .rightCommand: return "Right ⌘ Command"
        case .rightShift:   return "Right ⇧ Shift"
        case .rightControl: return "Right ⌃ Control"
        case .fn:           return "Fn / Globe"
        }
    }

    /// Virtual key code for the physical key.
    var keyCode: UInt16 {
        switch self {
        case .rightCommand: return 54
        case .rightOption:  return 61
        case .rightShift:   return 60
        case .rightControl: return 62
        case .fn:           return 63
        }
    }

    /// Modifier flag that should be set when this key is *down*.
    var matchingFlag: NSEvent.ModifierFlags {
        switch self {
        case .rightCommand: return .command
        case .rightOption:  return .option
        case .rightShift:   return .shift
        case .rightControl: return .control
        case .fn:           return .function
        }
    }
}

/// Tracks press/release of a single configured modifier key.
/// Uses NSEvent global + local flag-changed monitors — no Input Monitoring permission required.
///
/// Three behaviors based on press duration:
///  - Released **before** `activationDelayMs` → emits `.tap` (toggle on/off)
///  - Held **past** `activationDelayMs` → emits `.holdStart` (push-to-talk begins)
///  - Released after holdStart → emits `.holdEnd` (push-to-talk stops)
final class HoldKeyMonitor {
    enum Event {
        case tap          // quick press; user wants toggle behavior
        case holdStart    // long-press activated
        case holdEnd      // long-press released
    }

    typealias Handler = (Event) -> Void

    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var isPhysicallyDown = false  // tracks the raw key state
    private var isActive = false           // tracks whether we've fired holdStart
    private var pendingActivation: DispatchWorkItem?

    private let handler: Handler
    private let key: HoldKey
    private let activationDelayMs: Int

    init(key: HoldKey, activationDelayMs: Int = 150, handler: @escaping Handler) {
        self.key = key
        self.activationDelayMs = activationDelayMs
        self.handler = handler
    }

    func start() {
        guard globalMonitor == nil else { return }
        let mask: NSEvent.EventTypeMask = [.flagsChanged]

        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] event in
            self?.evaluate(event: event)
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
            self?.evaluate(event: event)
            return event
        }
        Log.hotkey.info("HoldKeyMonitor started (key=\(self.key.rawValue), delay=\(self.activationDelayMs)ms)")
    }

    func stop() {
        if let m = globalMonitor { NSEvent.removeMonitor(m) }
        if let m = localMonitor  { NSEvent.removeMonitor(m) }
        globalMonitor = nil
        localMonitor = nil
        pendingActivation?.cancel()
        pendingActivation = nil
        isPhysicallyDown = false
        isActive = false
    }

    private func evaluate(event: NSEvent) {
        // Only react to flag changes for the configured physical key.
        guard event.keyCode == key.keyCode else { return }
        let down = event.modifierFlags.contains(key.matchingFlag)
        guard down != isPhysicallyDown else { return }
        isPhysicallyDown = down

        if down {
            // Schedule activation; if user releases before delay elapses, fires .tap below.
            let work = DispatchWorkItem { [weak self] in
                guard let self else { return }
                guard self.isPhysicallyDown else { return }
                self.isActive = true
                self.handler(.holdStart)
            }
            pendingActivation = work
            DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(activationDelayMs), execute: work)
        } else {
            // Released. Cancel pending activation if it hadn't fired.
            let hadPendingActivation = pendingActivation != nil
            pendingActivation?.cancel()
            pendingActivation = nil
            if isActive {
                isActive = false
                handler(.holdEnd)
            } else if hadPendingActivation {
                // Released before activation threshold — quick tap.
                handler(.tap)
            }
        }
    }
}
