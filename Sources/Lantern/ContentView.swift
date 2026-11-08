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
            SelfTest.runIfRequested(model: model)
            Snapshot.runIfRequested(model: model, openSettings: openSettings)
            guard !SelfTest.requested, !Snapshot.requested else { return }
            model.repairInterruptedReplies()
            await model.connect()
        }
    }
}
