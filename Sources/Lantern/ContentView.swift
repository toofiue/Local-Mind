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
        .task {
            SeedData.insertIfRequested(into: model)
            QuickAskController.shared.configure(model: model)
            SelfTest.runIfRequested(model: model)
            Snapshot.runIfRequested(model: model, openSettings: openSettings)
            model.openMainWindow = { openWindow(id: "main") }
            guard !SelfTest.requested, !Snapshot.requested, !model.hasStarted else { return }
            model.hasStarted = true
            GlobalHotKey.shared.onPress = { QuickAskController.shared.toggle() }
            GlobalHotKey.shared.register()
            model.repairInterruptedReplies()
            await model.connect()
            await model.monitorLoadedModels()
        }
    }
}
