import Foundation
import Observation
import LanternKit

enum WritingPhase: Equatable {
    case loading(String), waiting
}

/// Writes one reply at a time, for any surface that asks.
/// Only one model fits in memory, so there's never more than one in progress.
@Observable
final class ReplyWriter {
    /// The reply being written. Snapshot mode sets it to show the writing state.
    var activeReplyID: UUID? { didSet { onChange() } }
    private(set) var activeConversationID: UUID?
    var phase: WritingPhase?

    @ObservationIgnored var onChange: () -> Void = {}
    /// Runs when a reply ends. The argument is true if the connection dropped.
    @ObservationIgnored var onFinished: (_ lostConnection: Bool) async -> Void = { _ in }
    @ObservationIgnored private var task: Task<Void, Never>?

    var isWriting: Bool { activeReplyID != nil }

    func isWriting(in conversation: Conversation) -> Bool {
        activeConversationID == conversation.uid
    }

    func start(_ reply: Message, in conversation: Conversation, modelName: String,
               turns: [ChatTurn], think: Bool, client: OllamaClient) {
        activeConversationID = conversation.uid
        activeReplyID = reply.uid
        phase = .waiting
        task = Task { await run(reply, in: conversation, modelName: modelName, turns: turns, think: think, client: client) }
    }

    func stop() {
        task?.cancel()
    }

    /// Lets the self-test wait for a reply to finish.
    func wait() async {
        await task?.value
    }

    private func run(_ reply: Message, in conversation: Conversation, modelName: String,
                     turns: [ChatTurn], think: Bool, client: OllamaClient) async {
        var text = ""
        var thinking = ""
        var lastFlush = ContinuousClock.now
        var lostConnection = false

        func flush() {
            reply.text = text
            reply.thinking = thinking
        }

        do {
            // Only one model fits in memory, so make room before loading. If
            // Ollama is too busy to say what's loaded, the chat request still queues.
            let loaded = (try? await client.loadedModels()) ?? []
            for other in loaded where other.name != modelName {
                try? await client.unload(other.name)
            }
            if !loaded.contains(where: { $0.name == modelName }) { phase = .loading(modelName) }

            for try await event in client.chat(model: modelName, turns: turns, think: think) {
                phase = nil
                switch event {
                case .thinking(let chunk): thinking += chunk
                case .text(let chunk): text += chunk
                case .done(let speed): reply.tokensPerSecond = speed
                }
                if ContinuousClock.now - lastFlush >= .milliseconds(50) {
                    flush()
                    lastFlush = .now
                }
            }
            try Task.checkCancellation()
            reply.state = .complete
        } catch is CancellationError {
            reply.state = .stopped
        } catch OllamaError.server(let message) {
            reply.state = .failed
            let nothingWritten = text.isEmpty && thinking.isEmpty
            reply.failureText = nothingWritten
                ? "Unable to load \(modelName). Close other apps to free memory, then click Retry."
                : "Unable to finish this reply. \(message)"
        } catch {
            reply.state = .interrupted
            lostConnection = true
        }

        flush()
        conversation.updatedAt = .now
        try? reply.modelContext?.save()
        activeConversationID = nil
        activeReplyID = nil
        phase = nil
        await onFinished(lostConnection)
    }
}
