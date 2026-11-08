import SwiftUI

struct ContentView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        NavigationSplitView {
            ConversationSidebar()
                .navigationSplitViewColumnWidth(min: 200, ideal: 260)
        } detail: {
            ConversationPage()
        }
        .task {
            SeedData.insertIfRequested(into: model)
            QuickAskController.shared.configure(model: model)
            SelfTest.runIfRequested(model: model)
            Snapshot.runIfRequested(model: model, openSettings: openSettings)
            guard !SelfTest.requested, !Snapshot.requested else { return }
            GlobalHotKey.shared.onPress = { QuickAskController.shared.toggle() }
            GlobalHotKey.shared.register()
            model.repairInterruptedReplies()
            await model.connect()
        }
    }
}
