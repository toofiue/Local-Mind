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
        List(selection: Binding(
            get: { model.isSelectingConversations ? model.multiSelection : Set(model.selection.map { [$0] } ?? []) },
            set: { picked in
                if model.isSelectingConversations {
                    // A plain click ticks or unticks one row, like a checkbox.
                    if picked.count == 1, let one = picked.first {
                        if model.multiSelection.contains(one) { model.multiSelection.remove(one) } else { model.multiSelection.insert(one) }
                    } else {
                        model.multiSelection = picked
                    }
                } else if picked.count > 1 {
                    // Command- or Shift-click starts picking several.
                    model.isSelectingConversations = true
                    model.multiSelection = picked
                } else {
                    model.selection = picked.first
                }
            })) {
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
        .safeAreaInset(edge: .top) {
            HomeRow()
        }
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
        }
        .help(conversation.title)
        .tag(conversation.uid)
        .accessibilityAddTraits(model.isSelectingConversations && model.multiSelection.contains(conversation.uid) ? .isSelected : [])
        .contextMenu {
            Button("Rename") { model.startRenaming(conversation) }
            Button(conversation.isPinned ? "Unpin" : "Pin") { model.togglePin(conversation) }
            Button("Select Multiple") {
                model.isSelectingConversations = true
                model.multiSelection = [conversation.uid]
            }
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

/// The way home: a new conversation, from any page. Highlighted while you're there.
private struct HomeRow: View {
    @Environment(AppModel.self) private var model

    private var isHome: Bool { model.selection == nil && !model.showingModels && model.labModelName == nil }

    var body: some View {
        Button { model.newConversation() } label: {
            Label("New Conversation", systemImage: "square.and.pencil")
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, Space.sm)
                .frame(minHeight: 28)
                .background(isHome ? AnyShapeStyle(.fill.secondary) : AnyShapeStyle(.clear),
                            in: RoundedRectangle(cornerRadius: Radius.md))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, Space.sm)
        .padding(.bottom, Space.xs)
        .help("Start a new conversation (⌘N)")
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
