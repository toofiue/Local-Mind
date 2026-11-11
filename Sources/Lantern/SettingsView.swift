import AppKit
import Carbon.HIToolbox
import LanternKit
import SwiftUI

/// The Settings window (Command-Comma). One tab per topic, at most about
/// six. Each tab is a grouped Form that sizes to its content, so the
/// window grows to fit and shows no scroll bar it does not need.
struct SettingsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        TabView(selection: $model.settingsTab) {
            ForEach(SettingsTab.allCases) { tab in
                page(tab)
                    .tabItem { Label(tab.title, systemImage: tab.symbol) }
                    .tag(tab)
            }
        }
        .noInitialFocus()
    }

    @ViewBuilder
    private func page(_ tab: SettingsTab) -> some View {
        Group {
            switch tab {
            case .general: GeneralSettings()
            case .appearance: AppearanceSettings()
            }
        }
        .frame(width: 640, height: 520)
    }
}

/// The Settings tabs. Snapshot mode walks through every case.
enum SettingsTab: String, CaseIterable, Identifiable {
    case general, appearance

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: "General"
        case .appearance: "Appearance"
        }
    }

    var symbol: String {
        switch self {
        case .general: "gearshape"
        case .appearance: "paintpalette"
        }
    }
}

/// Settings > General: Quick Ask's shortcut and the menu bar item.
/// The default model and how long models stay loaded live on the Models page, with the models.
struct GeneralSettings: View {
    @Environment(AppModel.self) private var model
    @AppStorage("showMenuBarItem") private var showMenuBarItem = true

    var body: some View {
        SettingsPageLayout(title: "General") {
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
                       description: "An aperture that opens when a model is loaded, with Quick Ask and Unload.") {
                Toggle("Show in the menu bar", isOn: $showMenuBarItem)
                    .labelsHidden()
                    .toggleStyle(.switch)
            }
            SettingRow(title: "Models", description: "The default model and how long models stay loaded are on the Models page.", divider: false) {
                Button("Open Models") {
                    model.showingSettings = false
                    model.showModels()
                }
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

