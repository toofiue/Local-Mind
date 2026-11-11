import SwiftData
import SwiftUI
import LanternKit

struct ConversationSidebar: View {
    @Environment(AppModel.self) private var model
    @Query(sort: \Conversation.updatedAt, order: .reverse) private var conversations: [Conversation]
    @FocusState private var isSearching: Bool

    private var isFiltering: Bool {
        !model.searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var results: [(conversation: Conversation, snippet: String)] {
        conversations.compactMap { conversation in
            ConversationSearch.snippet(for: model.searchText, title: conversation.title,
                                       messages: conversation.ordered.map(\.text))
                .map { (conversation, $0) }
        }
    }

    var body: some View {
        @Bindable var model = model
        let groups = ConversationGroups.split(conversations, isPinned: \.isPinned, updatedAt: \.updatedAt)
        let found = isFiltering ? results : []
        List(selection: $model.selection) {
            if isFiltering {
                ForEach(found, id: \.conversation.uid) { result in
                    ConversationRow(conversation: result.conversation, snippet: result.snippet)
                }
            } else if groups.pinned.isEmpty {
                rows(groups.recent)
            } else {
                Section("Pinned") { rows(groups.pinned) }
                Section("Recent") { rows(groups.recent) }
            }
        }
        // See-through to the desktop, like Finder's and Mail's sidebars.
        .scrollContentBackground(.hidden)
        .background(SidebarGlass().ignoresSafeArea())
        .searchable(text: $model.searchText, placement: .sidebar, prompt: "Search")
        .searchFocused($isSearching)
        .onChange(of: model.searchRequest) { isSearching = true }
        .safeAreaInset(edge: .bottom) {
            Button { model.showModels() } label: {
                Label("Models", systemImage: "cpu")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(model.showingModels ? Palette.accentText : .secondary)
            .padding(.horizontal, Space.lg)
            .padding(.vertical, Space.md)
            .help("See installed models and what's using memory (⇧⌘L)")
        }
        .onDeleteCommand { model.requestDelete() }
        .confirmationDialog(
            "Delete “\(model.pendingDeletion?.title ?? "")”?",
            isPresented: Binding(get: { model.pendingDeletion != nil }, set: { if !$0 { model.pendingDeletion = nil } }),
            presenting: model.pendingDeletion
        ) { conversation in
            Button("Delete", role: .destructive) { model.delete(conversation) }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("You can't undo this action.")
        }
        .overlay {
            if isFiltering && found.isEmpty {
                ContentUnavailableView.search(text: model.searchText)
            } else if conversations.isEmpty {
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

    private func rows(_ items: [Conversation]) -> some View {
        ForEach(items) { conversation in
            ConversationRow(conversation: conversation)
        }
    }
}

private struct ConversationRow: View {
    let conversation: Conversation
    /// Shown in place of the date when this row is a search result.
    var snippet: String?
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
            if let snippet {
                Text(snippet)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            } else {
                Text(conversation.updatedAt, format: .relative(presentation: .named))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .help(conversation.title)
        .tag(conversation.uid)
        .contextMenu {
            Button("Rename") { model.startRenaming(conversation) }
            Button(conversation.isPinned ? "Unpin" : "Pin") { model.togglePin(conversation) }
            Divider()
            Button("Delete", role: .destructive) { model.requestDelete(conversation) }
                .disabled(model.isWriting(in: conversation))
        }
    }
}
