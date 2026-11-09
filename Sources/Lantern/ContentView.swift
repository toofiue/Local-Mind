import AppKit
import SwiftUI

struct ContentView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openSettings) private var openSettings
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        NavigationSplitView {
            ConversationSidebar()
                .navigationSplitViewColumnWidth(min: 200, ideal: 260)
        } detail: {
            if model.showingModels {
                ModelsPage()
            } else {
                ConversationPage()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            Task { await model.refreshInstalledModels() }
        }
        .task {
            SeedData.insertIfRequested(into: model)
            QuickAskController.shared.configure(model: model)
            SelfTest.runIfRequested(model: model)
            Snapshot.runIfRequested(model: model, openSettings: openSettings)
            model.openMainWindow = { openWindow(id: "main") }
            guard !SelfTest.requested, !Snapshot.requested, !model.hasStarted else { return }
            model.hasStarted = true
            GlobalHotKey.shared.onPress = { QuickAskController.shared.toggle() }
            if !GlobalHotKey.shared.register(model.hotkey) {
                model.hotkeyMessage = "Another app already uses \(model.hotkey.display). Choose another."
            }
            model.repairInterruptedReplies()
            await model.connect()
            await model.monitorLoadedModels()
        }
    }
}
