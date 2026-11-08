import SwiftData
import SwiftUI

struct ConversationSidebar: View {
    @Environment(AppModel.self) private var model
    @Query(sort: \Conversation.updatedAt, order: .reverse) private var conversations: [Conversation]

    var body: some View {
        @Bindable var model = model
        List(selection: $model.selection) {
            ForEach(conversations) { conversation in
                ConversationRow(conversation: conversation)
            }
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

private struct ConversationRow: View {
    let conversation: Conversation
    @Environment(AppModel.self) private var model
    @State private var draft = ""
    @FocusState private var isEditing: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            if model.renamingID == conversation.uid {
                TextField("Title", text: $draft)
                    .labelsHidden()
                    .focused($isEditing)
                    .onSubmit { model.rename(conversation, to: draft) }
                    .onExitCommand { model.finishRenaming() }
                    .onChange(of: isEditing) { _, editing in
                        // Clicking away saves, as it does in Finder.
                        if !editing, model.renamingID == conversation.uid { model.rename(conversation, to: draft) }
                    }
                    .task {
                        draft = conversation.title
                        // A list row can't take focus until it has been laid out.
                        try? await Task.sleep(for: .milliseconds(50))
                        isEditing = true
                    }
            } else {
                Text(conversation.title)
                    .lineLimit(1)
            }
            Text(conversation.updatedAt, format: .relative(presentation: .named))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .help(conversation.title)
        .tag(conversation.uid)
        .contextMenu {
            Button("Rename") { model.startRenaming(conversation) }
        }
    }
}
