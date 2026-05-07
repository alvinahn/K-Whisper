import Foundation
import Carbon.HIToolbox
import AppKit

/// Wraps Carbon `RegisterEventHotKey` for a single global toggle hotkey.
final class CarbonHotkey {
    typealias Handler = () -> Void

    private var hotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?
    private let handler: Handler
    private static var sharedHandlers: [UInt32: Handler] = [:]
    private static var nextID: UInt32 = 1
    private let hotKeyID: UInt32

    init(keyCode: Int, modifiers: Int, handler: @escaping Handler) {
        self.handler = handler
        self.hotKeyID = Self.nextID
        Self.nextID += 1
        Self.sharedHandlers[hotKeyID] = handler

        installEventHandlerIfNeeded()

        let hkID = EventHotKeyID(signature: OSType(0x564F5841 /* "VOXA" */), id: hotKeyID)
        let status = RegisterEventHotKey(
            UInt32(keyCode),
            UInt32(modifiers),
            hkID,
            GetEventDispatcherTarget(),
            0,
            &hotKeyRef
        )
        if status != noErr {
            Log.hotkey.error("RegisterEventHotKey failed: \(status)")
        }
    }

    deinit {
        if let ref = hotKeyRef {
            UnregisterEventHotKey(ref)
        }
        Self.sharedHandlers.removeValue(forKey: hotKeyID)
    }

    private static var globalHandlerInstalled = false
    private func installEventHandlerIfNeeded() {
        guard !Self.globalHandlerInstalled else { return }
        Self.globalHandlerInstalled = true

        var spec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        InstallEventHandler(
            GetEventDispatcherTarget(),
            { _, eventRef, _ in
                guard let eventRef = eventRef else { return noErr }
                var hkID = EventHotKeyID()
                let s = GetEventParameter(
                    eventRef,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hkID
                )
                guard s == noErr else { return s }
                if let h = CarbonHotkey.sharedHandlers[hkID.id] {
                    DispatchQueue.main.async { h() }
                }
                return noErr
            },
            1,
            &spec,
            nil,
            nil
        )
    }
}
