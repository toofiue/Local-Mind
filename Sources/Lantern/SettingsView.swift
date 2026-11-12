import AppKit
import Carbon.HIToolbox
import LanternKit
import SwiftUI

/// Settings > General: Quick Ask's shortcut and the menu bar item.
struct GeneralSettings: View {
    @Environment(AppModel.self) private var model
    @AppStorage("showMenuBarItem") private var showMenuBarItem = true
    @State private var opensAtLogin = LoginItem.isEnabled
    @State private var loginProblem: String?

    var body: some View {
        SettingsPageLayout(title: "General") {
            SettingRow(title: "Open at login",
                       description: loginProblem ?? "Starts quietly in the menu bar when you log in, so the Quick Ask shortcut always works. No window opens.") {
                Toggle("Open at login", isOn: Binding(get: { opensAtLogin }, set: { on in
                    loginProblem = LoginItem.set(on)
                    opensAtLogin = LoginItem.isEnabled
                }))
                .labelsHidden()
                .toggleStyle(.switch)
            }
            SettingRow(title: "Quick Ask shortcut",
                       description: model.hotkeyMessage ?? "Opens Quick Ask from any app while Local Mind is running.") {
                HStack(spacing: Space.sm) {
                    if model.hotkey != .standard {
                        Button("Use Default") { model.changeHotkey(.standard) }
                    }
                    ShortcutRecorder()
                }
            }
            SettingRow(title: "Show in the menu bar",
                       description: "An aperture that opens when a model is loaded, with Quick Ask and Unload. Closing the window keeps Local Mind running here.",
                       divider: false) {
                Toggle("Show in the menu bar", isOn: $showMenuBarItem)
                    .labelsHidden()
                    .toggleStyle(.switch)
            }
        }
    }
}

/// A button that records the next key combination you press.
private struct ShortcutRecorder: View {
    @Environment(AppModel.self) private var model
    @State private var monitor: Any?

    var body: some View {
        Button(monitor == nil ? model.hotkey.display : "Type a Shortcut…") {
            if monitor == nil { startRecording() } else { stopRecording() }
        }
        .help("Change the shortcut that opens Quick Ask")
        .accessibilityLabel("Shortcut")
        .accessibilityValue(model.hotkey.display)
        .onDisappear { stopRecording() }
    }

    private func startRecording() {
        model.hotkeyMessage = nil
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if Int(event.keyCode) != kVK_Escape {
                model.changeHotkey(Hotkey(keyCode: Int(event.keyCode), modifiers: carbonModifiers(event.modifierFlags)))
            }
            stopRecording()
            return nil
        }
    }

    private func stopRecording() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }

    private func carbonModifiers(_ flags: NSEvent.ModifierFlags) -> Int {
        var result = 0
        if flags.contains(.command) { result |= cmdKey }
        if flags.contains(.control) { result |= controlKey }
        if flags.contains(.option) { result |= optionKey }
        if flags.contains(.shift) { result |= shiftKey }
        return result
    }
}

