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
        let progress = messages.last.map { $0.text.count + $0.thinking.count } ?? 0

        ScrollView {
            LazyVStack(spacing: Space.xxl) {
                ForEach(messages) { message in
                    MessageRow(message: message, isLatestReply: message.uid == latestReplyID)
                }
            }
            .frame(maxWidth: Layout.column)
            .padding(Space.margin)
            .frame(maxWidth: .infinity)
        }
        .defaultScrollAnchor(.bottom)
        .scrollPosition($position)
        .onScrollGeometryChange(for: ScrollMetrics.self) { geometry in
            let visibleBottom = geometry.contentOffset.y + geometry.containerSize.height
            // Short conversations sit at the bottom with nothing to scroll.
            let fits = geometry.contentSize.height <= geometry.containerSize.height
            return ScrollMetrics(offset: geometry.contentOffset.y,
                                 isAtBottom: fits || visibleBottom >= geometry.contentSize.height - Space.section)
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

    var body: some View {
        switch message.role {
        case .user:
            HStack {
                Spacer(minLength: Space.section)
                VStack(alignment: .trailing, spacing: Space.sm) {
                    if !message.attachments.isEmpty { SentAttachmentRow(message: message) }
                    Text(message.text)
                        .textSelection(.enabled)
                        .padding(.horizontal, Space.md)
                        .padding(.vertical, Space.sm)
                        .background(.fill.tertiary, in: RoundedRectangle(cornerRadius: Radius.lg))
                }
            }
        case .assistant:
            ReplyRow(message: message, isLatestReply: isLatestReply)
        }
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
                        Button("Retry", systemImage: "arrow.clockwise") { model.retry() }
                            .help("Replace this reply with a new one (⌘R)")
                            .disabled(model.isWriting)
                    }
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var progressText: String {
        if case .loading(let name) = model.writingPhase, model.writingReplyID == message.uid {
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
