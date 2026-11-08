import Carbon.HIToolbox

/// The system-wide shortcut. It needs no permission, and the key press never
/// reaches the app in front.
final class GlobalHotKey {
    static let shared = GlobalHotKey()

    var onPress: () -> Void = {}
    private var reference: EventHotKeyRef?
    private var isHandlerInstalled = false

    /// Returns false if another app already owns the shortcut.
    @discardableResult
    func register(keyCode: Int = kVK_Space, modifiers: Int = controlKey | optionKey) -> Bool {
        if !isHandlerInstalled {
            var type = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
            InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
                Task { @MainActor in GlobalHotKey.shared.onPress() }
                return noErr
            }, 1, &type, nil, nil)
            isHandlerInstalled = true
        }
        if let reference { UnregisterEventHotKey(reference) }
        reference = nil
        let id = EventHotKeyID(signature: OSType(0x4C4E_544E), id: 1) // 'LNTN'
        return RegisterEventHotKey(UInt32(keyCode), UInt32(modifiers), id, GetApplicationEventTarget(), 0, &reference) == noErr
    }
}
