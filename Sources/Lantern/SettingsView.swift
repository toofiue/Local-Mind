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
        Form {
            switch tab {
            case .models: ModelsSettings()
            case .appearance: AppearanceSettings()
            }
        }
        .formStyle(.grouped)
        .fitsContent()
        .frame(width: 520)
    }
}

/// The Settings tabs. Snapshot mode walks through every case.
enum SettingsTab: String, CaseIterable, Identifiable {
    case models, appearance

    var id: String { rawValue }

    var title: String {
        switch self {
        case .models: "Models"
        case .appearance: "Appearance"
        }
    }

    var symbol: String {
        switch self {
        case .models: "cpu"
        case .appearance: "paintpalette"
        }
    }
}

struct ModelsSettings: View {
    @Environment(AppModel.self) private var model
    @AppStorage("showMenuBarItem") private var showMenuBarItem = true

    var body: some View {
        @Bindable var model = model
        Section {
            Picker("Keep a model loaded for", selection: $model.keepLoadedMinutes) {
                ForEach([1, 5, 15, 30], id: \.self) { minutes in
                    Text("^[\(minutes) minute](inflect: true)").tag(minutes)
                }
            }
        } footer: {
            Text("After its last reply. Models use a lot of memory while loaded.")
        }
        Section {
            Toggle("Show Lantern in the menu bar", isOn: $showMenuBarItem)
        }
    }
}
