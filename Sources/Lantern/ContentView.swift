import SwiftData
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

struct ConversationSidebar: View {
    @Environment(AppModel.self) private var model
    @Query(sort: \Conversation.updatedAt, order: .reverse) private var conversations: [Conversation]

    var body: some View {
        @Bindable var model = model
        List(conversations, selection: $model.selection) { conversation in
            VStack(alignment: .leading, spacing: Space.xs) {
                Text(conversation.title)
                    .lineLimit(1)
                Text(conversation.updatedAt, format: .relative(presentation: .named))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .help(conversation.title)
            .tag(conversation.uid)
        }
        .overlay {
            if conversations.isEmpty {
                ContentUnavailableView {
                    Label("No Conversations", systemImage: "bubble.left.and.bubble.right")
                } description: {
                    Text("Conversations you start appear here.")
                } actions: {
                    Button("New Conversation") { model.newConversation() }
                }
            }
        }
    }
}
