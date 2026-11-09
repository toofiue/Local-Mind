import Carbon.HIToolbox
import LanternKit

/// The system-wide shortcut. It needs no permission, and the key press never
/// reaches the app in front.
final class GlobalHotKey {
    static let shared = GlobalHotKey()

    var onPress: () -> Void = {}
    private var reference: EventHotKeyRef?
    private var isHandlerInstalled = false

    /// Returns false if another app owns the shortcut. The current one then keeps working.
    @discardableResult
    func register(_ hotkey: Hotkey) -> Bool {
        if !isHandlerInstalled {
            var type = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
            InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
                Task { @MainActor in GlobalHotKey.shared.onPress() }
                return noErr
            }, 1, &type, nil, nil)
            isHandlerInstalled = true
        }
        let id = EventHotKeyID(signature: OSType(0x4C4E_544E), id: 1) // 'LNTN'
        var replacement: EventHotKeyRef?
        guard RegisterEventHotKey(UInt32(hotkey.keyCode), UInt32(hotkey.modifiers), id,
                                  GetApplicationEventTarget(), 0, &replacement) == noErr else { return false }
        unregister()
        reference = replacement
        return true
    }

    func unregister() {
        if let reference { UnregisterEventHotKey(reference) }
        reference = nil
    }

    /// True if macOS itself uses this shortcut and it's turned on, such as ⌘Space for Spotlight.
    static func isReservedBySystem(_ hotkey: Hotkey) -> Bool {
        var result: Unmanaged<CFArray>?
        guard CopySymbolicHotKeys(&result) == noErr,
              let entries = result?.takeRetainedValue() as? [[String: Any]] else { return false }
        let mask = cmdKey | controlKey | optionKey | shiftKey
        return entries.contains { entry in
            (entry[kHISymbolicHotKeyEnabled as String] as? Bool) == true
                && (entry[kHISymbolicHotKeyCode as String] as? Int) == hotkey.keyCode
                && ((entry[kHISymbolicHotKeyModifiers as String] as? Int) ?? 0) & mask == hotkey.modifiers & mask
        }
    }
}
