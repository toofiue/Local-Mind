import AppKit
import SwiftUI

/// The bulb in the menu bar, filled while a model is in memory.
struct LanternMenuLabel: View {
    let model: AppModel

    var body: some View {
        Image(systemName: model.loaded.isEmpty ? "lightbulb" : "lightbulb.fill")
            .accessibilityLabel("Lantern")
    }
}

struct LanternMenu: View {
    let model: AppModel

    var body: some View {
        if let loaded = model.loaded.first {
            Text("\(model.displayName(loaded.name)) · \(loaded.memory, format: .byteCount(style: .file))")
        } else {
            Text("No Model Loaded")
        }
        Divider()
        Button("Quick Ask") { QuickAskController.shared.show() }
        Button("Unload") {
            if let name = model.loaded.first?.name { Task { await model.unload(name) } }
        }
        .disabled(model.loaded.first.map { !model.canUnload($0.name) } ?? true)
        Divider()
        Button("Open Lantern") { model.showMainWindow() }
        Button("Quit Lantern") { NSApp.terminate(nil) }
    }
}
