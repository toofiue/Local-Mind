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
        // Rows handle clicks themselves: one click opens, a double-click renames,
        // and the highlight is a soft wash of the accent instead of the system's blue.
        List {
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
            if model.isSelectingConversations {
                SelectionBar(all: conversations.map(\.uid))
            } else {
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
        }
        .onExitCommand { model.isSelectingConversations = false }
        .onMoveCommand { direction in
            if direction == .up { model.selectAdjacentConversation(by: -1) }
            if direction == .down { model.selectAdjacentConversation(by: 1) }
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
        .confirmationDialog(
            model.pendingDeletions.count == 1 ? "Delete “\(model.pendingDeletions.first?.title ?? "")”?"
                : "Delete \(model.pendingDeletions.count) conversations?",
            isPresented: Binding(get: { !model.pendingDeletions.isEmpty }, set: { if !$0 { model.pendingDeletions = [] } })
        ) {
            Button(model.pendingDeletions.count == 1 ? "Delete" : "Delete \(model.pendingDeletions.count) Conversations",
                   role: .destructive) { model.delete(model.pendingDeletions) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("You can't undo this action.")
        }
        .overlay {
            if isFiltering && found.isEmpty {
                ContentUnavailableView.search(text: model.searchText)
            } else if conversations.isEmpty {
                // No button here: New Conversation is always at the top of the sidebar.
                ContentUnavailableView {
                    Label("No Conversations", systemImage: "bubble.left.and.bubble.right")
                } description: {
                    Text("Conversations you start appear here.")
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

    private var isPicked: Bool { model.multiSelection.contains(conversation.uid) }
    private var isOpen: Bool { model.selection == conversation.uid && !model.showingModels && model.labModelName == nil }
    private var isHighlighted: Bool { model.isSelectingConversations ? isPicked : isOpen }

    /// A soft wash of the accent: stronger for the open chat or a ticked one.
    private var highlight: Color {
        isHighlighted ? Palette.accent.opacity(0.16) : .clear
    }

    private func click() {
        if model.isSelectingConversations {
            if isPicked { model.multiSelection.remove(conversation.uid) } else { model.multiSelection.insert(conversation.uid) }
        } else if model.selection != conversation.uid || model.showingModels || model.labModelName != nil {
            model.selection = conversation.uid
        }
    }

    private func startPicking() {
        guard !model.isSelectingConversations else { return }
        model.isSelectingConversations = true
        model.multiSelection = [conversation.uid]
    }

    var body: some View {
        HStack(spacing: Space.sm) {
        if model.isSelectingConversations {
            Image(systemName: model.multiSelection.contains(conversation.uid) ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(model.multiSelection.contains(conversation.uid) ? AnyShapeStyle(.tint) : AnyShapeStyle(.tertiary))
                .font(.title3)
                .accessibilityHidden(true)
        }
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
                        // A list row can't take focus until it has been laid out, and a double-click's
                        // first click has just opened the chat, so wait for that to settle.
                        try? await Task.sleep(for: .milliseconds(150))
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
        }
        .help(conversation.title)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .onTapGesture { click() }
        // A double-click renames, as in Finder. It fires after the first click opened the chat.
        .simultaneousGesture(TapGesture(count: 2).onEnded {
            if !model.isSelectingConversations { model.startRenaming(conversation) }
        })
        .listRowBackground(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .fill(highlight)
                .padding(.horizontal, Space.sm)
        )
        // While renaming, the row is a text field, not a button.
        .accessibilityAddTraits(model.renamingID == conversation.uid ? [] : .isButton)
        .accessibilityAddTraits(isHighlighted ? .isSelected : [])
        .accessibilityAction(named: "Rename") { model.startRenaming(conversation) }
        .accessibilityAction(named: "Select Multiple") { startPicking() }
        .contextMenu {
            Button("Rename") { model.startRenaming(conversation) }
            Button(conversation.isPinned ? "Unpin" : "Pin") { model.togglePin(conversation) }
            Button("Select Multiple", action: startPicking)
            Divider()
            if model.isSelectingConversations, model.multiSelection.contains(conversation.uid) {
                Button(model.multiSelection.count == 1 ? "Delete" : "Delete \(model.multiSelection.count) Conversations",
                       role: .destructive) { model.requestDelete(conversation) }
            } else {
                Button("Delete", role: .destructive) { model.requestDelete(conversation) }
                    .disabled(model.isWriting(in: conversation))
            }
        }
    }
}

/// Shown at the bottom of the sidebar while picking several conversations.
private struct SelectionBar: View {
    let all: [UUID]
    @Environment(AppModel.self) private var model

    private var count: Int { model.multiSelection.count }
    private var everything: Bool { !all.isEmpty && count == all.count }

    var body: some View {
        VStack(spacing: Space.sm) {
            HStack {
                Text(count == 0 ? "Select Conversations" : "\(count) Selected")
                    .font(.callout.weight(.medium))
                Spacer()
                Button(everything ? "Deselect All" : "Select All") {
                    model.multiSelection = everything ? [] : Set(all)
                }
                .buttonStyle(.borderless)
            }
            HStack {
                Button("Cancel") { model.isSelectingConversations = false }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Delete", role: .destructive) { model.requestDelete() }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                    .disabled(count == 0)
                    .help("Delete the selected conversations")
            }
        }
        .padding(Space.md)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: Radius.lg))
        .padding(Space.sm)
    }
}
