import AppKit
import Carbon.HIToolbox

/// Registers a system-wide global hotkey (Ctrl+Shift+Space) that works even when the app is in the background.
/// Uses Carbon RegisterEventHotKey which works inside App Sandbox without Accessibility permissions.
final class GlobalHotkeyManager {
    static let shared = GlobalHotkeyManager()

    var onHotkeyPressed: (() -> Void)?

    private var hotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?

    // Hotkey ID
    private let hotkeyID = EventHotKeyID(signature: OSType(0x5446_4C57), // "TFLW"
                                          id: 1)

    private init() {}

    /// Registers the global hotkey. Call once at app launch.
    func register() {
        // Already registered
        guard hotKeyRef == nil else { return }

        // Install Carbon event handler
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                      eventKind: UInt32(kEventHotKeyPressed))

        let handler: EventHandlerUPP = { _, event, _ -> OSStatus in
            GlobalHotkeyManager.shared.onHotkeyPressed?()
            return noErr
        }

        InstallEventHandler(
            GetApplicationEventTarget(),
            handler,
            1,
            &eventType,
            nil,
            &eventHandlerRef
        )

        // Register: Ctrl + Shift + Space
        // Key code 49 = Space bar
        let modifiers: UInt32 = UInt32(controlKey | shiftKey)
        RegisterEventHotKey(
            UInt32(kVK_Space),
            modifiers,
            hotkeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
    }

    /// Unregisters the global hotkey.
    func unregister() {
        if let ref = hotKeyRef {
            UnregisterEventHotKey(ref)
            hotKeyRef = nil
        }
        if let ref = eventHandlerRef {
            RemoveEventHandler(ref)
            eventHandlerRef = nil
        }
    }

    deinit {
        unregister()
    }
}
