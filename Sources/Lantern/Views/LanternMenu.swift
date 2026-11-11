import AppKit
import SwiftUI

extension AppModel {
    /// Open while a model is in memory, half open while one is loading for a reply or test.
    var apertureState: ApertureIcon.State {
        if !loaded.isEmpty { return .open }
        return isWriting ? .opening : .closed
    }
}

/// The aperture in the menu bar, which shows at a glance whether a model is on.
struct LanternMenuLabel: View {
    let model: AppModel

    var body: some View {
        Image(nsImage: ApertureIcon.image(model.apertureState))
            .accessibilityLabel(model.apertureState.label)
            .help(model.apertureState.label)
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
        Button("Open Iris") { model.showMainWindow() }
        Button("Quit Iris") { NSApp.terminate(nil) }
    }
}
