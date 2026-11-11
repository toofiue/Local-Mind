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
            case .models: ModelsSettings()
            case .quickAsk: QuickAskSettings()
            case .appearance: AppearanceSettings()
            }
        }
        .frame(width: 640, height: 520)
    }
}

/// The Settings tabs. Snapshot mode walks through every case.
enum SettingsTab: String, CaseIterable, Identifiable {
    case models, quickAsk, appearance

    var id: String { rawValue }

    var title: String {
        switch self {
        case .models: "Models"
        case .quickAsk: "Quick Ask"
        case .appearance: "Appearance"
        }
    }

    var symbol: String {
        switch self {
        case .models: "cpu"
        case .quickAsk: "bolt"
        case .appearance: "paintpalette"
        }
    }
}

struct QuickAskSettings: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        SettingsPageLayout(title: "Quick Ask") {
            SettingRow(title: "Shortcut",
                       description: model.hotkeyMessage ?? "Opens Quick Ask from any app while Local Mind is running.",
                       divider: false) {
                HStack(spacing: Space.sm) {
                    if model.hotkey != .standard {
                        Button("Use Default") { model.changeHotkey(.standard) }
                    }
                    ShortcutRecorder()
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

struct ModelsSettings: View {
    @Environment(AppModel.self) private var model
    @AppStorage("showMenuBarItem") private var showMenuBarItem = true

    var body: some View {
        @Bindable var model = model
        SettingsPageLayout(title: "Models") {
            SettingRow(title: "Default model", description: "Used for new conversations. Last Used picks the one you used most recently.") {
                Picker("Default model", selection: $model.chosenDefaultModel) {
                    Text("Last Used").tag("")
                    Divider()
                    ForEach(model.models) { item in
                        Text(model.displayName(item.name)).tag(item.name)
                    }
                }
                .labelsHidden()
                .fixedSize()
            }
            SettingRow(title: "Keep a model loaded", description: "How long a model stays in memory after its last reply. Loaded models answer at once but use a lot of memory.") {
                Picker("Keep a model loaded", selection: $model.keepLoadedMinutes) {
                    ForEach([1, 5, 15, 30], id: \.self) { minutes in
                        Text("^[\(minutes) minute](inflect: true)").tag(minutes)
                    }
                }
                .labelsHidden()
                .fixedSize()
            }
            SettingRow(title: "Show in the menu bar", description: "An aperture that opens when a model is loaded, with Quick Ask and Unload.", divider: false) {
                Toggle("Show in the menu bar", isOn: $showMenuBarItem)
                    .labelsHidden()
                    .toggleStyle(.switch)
            }
        }
    }
}
