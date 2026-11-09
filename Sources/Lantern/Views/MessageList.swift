import SwiftUI

private struct ScrollMetrics: Equatable {
    var offset: CGFloat
    var isAtBottom: Bool
}

struct MessageList: View {
    let conversation: Conversation
    @Environment(AppModel.self) private var model
    @State private var position = ScrollPosition(edge: .bottom)
    @State private var isFollowing = true
    @State private var isUserScrolling = false

    var body: some View {
        let messages = conversation.ordered
        let latestReplyID = messages.last { $0.role == .assistant }?.uid
        let latestUserID = messages.last { $0.role == .user }?.uid
        let progress = messages.last.map { $0.text.count + $0.thinking.count } ?? 0

        ScrollView {
            LazyVStack(spacing: Space.xxl) {
                ForEach(messages) { message in
                    MessageRow(message: message, isLatestReply: message.uid == latestReplyID,
                               canEdit: message.uid == latestUserID)
                }
            }
            .frame(maxWidth: Layout.column)
            .padding(Space.margin)
            .frame(maxWidth: .infinity)
        }
        .defaultScrollAnchor(.bottom)
        .scrollPosition($position)
        .onScrollGeometryChange(for: ScrollMetrics.self) { geometry in
            // visibleRect accounts for the toolbar over the top of the list. Adding the
            // offset to the container height comes up one toolbar short at the real bottom.
            ScrollMetrics(offset: geometry.contentOffset.y,
                          isAtBottom: geometry.visibleRect.maxY >= geometry.contentSize.height - Space.section)
        } action: { old, new in
            // The offset also shifts while a long list measures itself, so only real scrolling counts.
            if new.isAtBottom {
                isFollowing = true
            } else if isUserScrolling && new.offset < old.offset - 1 {
                isFollowing = false
            }
        }
        .onScrollPhaseChange { _, phase in
            isUserScrolling = phase == .tracking || phase == .interacting || phase == .decelerating
        }
        .onChange(of: progress) {
            if isFollowing { position.scrollTo(edge: .bottom) }
        }
        .overlay(alignment: .bottom) {
            if !isFollowing {
                Button("Jump to Latest", systemImage: "arrow.down") {
                    isFollowing = true
                    position.scrollTo(edge: .bottom)
                }
                .buttonStyle(.glass)
                .padding(.bottom, Space.md)
            }
        }
    }
}

struct MessageRow: View {
    let message: Message
    let isLatestReply: Bool
    /// Only the latest message in the main window can be changed.
    var canEdit = false
    @Environment(AppModel.self) private var model

    var body: some View {
        switch message.role {
        case .user:
            HStack {
                Spacer(minLength: Space.section)
                VStack(alignment: .trailing, spacing: Space.sm) {
                    if !message.attachments.isEmpty { SentAttachmentRow(message: message) }
                    if model.editingMessageID == message.uid {
                        EditMessageField(message: message)
                    } else {
                        Text(message.text)
                            .textSelection(.enabled)
                            .padding(.horizontal, Space.md)
                            .padding(.vertical, Space.sm)
                            .background(.fill.tertiary, in: RoundedRectangle(cornerRadius: Radius.lg))
                        if canEdit {
                            Button("Edit Message", systemImage: "pencil") { model.startEditing() }
                                .labelStyle(.iconOnly)
                                .buttonStyle(.borderless)
                                .foregroundStyle(.secondary)
                                .disabled(model.isWriting)
                                .help("Change this message and write a new reply (⇧⌘E)")
                        }
                    }
                }
            }
        case .assistant:
            ReplyRow(message: message, isLatestReply: isLatestReply)
        }
    }
}

private struct EditMessageField: View {
    let message: Message
    @Environment(AppModel.self) private var model
    @State private var draft: String
    @State private var height: CGFloat = Space.lg

    init(message: Message) {
        self.message = message
        _draft = State(initialValue: message.text)
    }

    var body: some View {
        // The native field leaves the cursor at the end instead of selecting everything.
        ComposerField(text: $draft, height: $height, isEnabled: true, focusRequest: 1, maxLines: 8,
                      onSubmit: { model.saveEdit(message, text: draft) },
                      onEscape: { model.cancelEditing() })
            .frame(height: height)
            .padding(.horizontal, Space.md)
            .padding(.vertical, Space.sm)
            .background(.fill.tertiary, in: RoundedRectangle(cornerRadius: Radius.lg))
            .frame(maxWidth: Layout.column)
    }
}

private struct ReplyRow: View {
    let message: Message
    let isLatestReply: Bool
    @Environment(AppModel.self) private var model

    private var isWriting: Bool { message.state == .writing }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            Text(message.modelName)
                .font(.caption)
                .foregroundStyle(.secondary)

            if !message.thinking.isEmpty {
                ThinkingSection(text: message.thinking, isStreaming: isWriting && message.text.isEmpty)
            }

            if isWriting && message.text.isEmpty && message.thinking.isEmpty {
                HStack(spacing: Space.sm) {
                    ProgressView().controlSize(.small)
                    Text(progressText).foregroundStyle(.secondary)
                }
            }

            if !message.text.isEmpty {
                MarkdownView(text: message.text)
            }

            if let notice {
                Label(notice.text, systemImage: notice.symbol)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            if !isWriting {
                HStack(spacing: Space.xs) {
                    if !message.text.isEmpty { CopyReplyButton(text: message.text) }
                    if isLatestReply {
                        Button("Retry", systemImage: "arrow.clockwise") { model.retry(message.conversation) }
                            .help("Replace this reply with a new one (⌘R)")
                            .disabled(model.isWriting)
                    }
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                if let speed = message.tokensPerSecond {
                    Text("\(Int(speed.rounded())) tokens per second")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var progressText: String {
        if case .loading(let name) = model.replies.phase, model.replies.activeReplyID == message.uid {
            return "Loading \(name)…"
        }
        return "Writing reply…"
    }

    private var notice: (text: String, symbol: String)? {
        switch message.state {
        case .stopped: ("Stopped", "stop.circle")
        case .interrupted: ("Interrupted. Lantern lost its connection to Ollama.", "exclamationmark.triangle")
        case .failed: (message.failureText, "exclamationmark.triangle")
        case .complete, .writing: nil
        }
    }
}

private struct CopyReplyButton: View {
    let text: String
    @State private var didCopy = false

    var body: some View {
        Button(didCopy ? "Copied" : "Copy Reply", systemImage: didCopy ? "checkmark" : "doc.on.doc") {
            Clipboard.copy(text)
            didCopy = true
            Task {
                try? await Task.sleep(for: Motion.confirmation)
                didCopy = false
            }
        }
        .help("Copy this reply as Markdown (⇧⌘C)")
    }
}

private struct ThinkingSection: View {
    let text: String
    let isStreaming: Bool
    @State private var isOpen = Snapshot.requested

    var body: some View {
        DisclosureGroup(isExpanded: Binding(get: { isStreaming || isOpen }, set: { isOpen = $0 })) {
            ScrollView {
                Text(text)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .defaultScrollAnchor(isStreaming ? .bottom : .top)
            .frame(maxHeight: 200)
            .padding(.top, Space.xs)
        } label: {
            Text(isStreaming ? "Thinking…" : "Thinking")
                .foregroundStyle(.secondary)
        }
    }
}
