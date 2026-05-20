import Carbon.HIToolbox
import AppKit

/// Lightweight wrapper around Carbon's RegisterEventHotKey.
/// No external dependencies, no accessibility permission required.
final class HotkeyManager {
    static let shared = HotkeyManager()

    private struct Registration {
        let id: UInt32
        let ref: EventHotKeyRef?
    }

    private var handlers: [UInt32: () -> Void] = [:]
    private var registrations: [Registration] = []
    private var nextID: UInt32 = 1
    private var installed = false

    private init() {
        installHandler()
    }

    private func installHandler() {
        guard !installed else { return }
        installed = true

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        InstallEventHandler(
            GetApplicationEventTarget(),
            { (_, event, _) -> OSStatus in
                guard let event else { return noErr }
                var hotKeyID = EventHotKeyID()
                GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hotKeyID
                )
                DispatchQueue.main.async {
                    HotkeyManager.shared.handlers[hotKeyID.id]?()
                }
                return noErr
            },
            1,
            &eventType,
            nil,
            nil
        )
    }

    /// Register a global hotkey. Returns true on success.
    @discardableResult
    func register(keyCode: Int, modifiers: Int, action: @escaping () -> Void) -> Bool {
        let id = nextID
        nextID += 1

        var ref: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: OSType(0x53544B59), id: id) // 'STKY'

        let status = RegisterEventHotKey(
            UInt32(keyCode),
            UInt32(modifiers),
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &ref
        )

        if status == noErr {
            handlers[id] = action
            registrations.append(Registration(id: id, ref: ref))
            return true
        } else {
            NSLog("StickyNotes: failed to register hotkey (status=\(status))")
            return false
        }
    }

    /// Unregister all currently-registered hotkeys. Call before re-registering
    /// when the user changes a binding.
    func unregisterAll() {
        for reg in registrations {
            if let ref = reg.ref {
                UnregisterEventHotKey(ref)
            }
        }
        registrations.removeAll()
        handlers.removeAll()
    }
}
