import AppKit
import SwiftData
import LanternKit

/// Sample data for snapshots: APP_SEED=1 with APP_STORE in /tmp fills an empty
/// store. Seed only what a person can create in the app, or the snapshots
/// show features no one can use.
@MainActor
enum SeedData {
    static let formatted = "Explain Swift actors with a short example"
    static let thinking = "Is a 16 GB Mac enough for local models?"
    static let writing = "Draft a short email asking to move our meeting"
    static let longTitle = "Summarize the differences between the three Gemma model sizes and when each one is the right choice"

    static let attached = "What is in this screenshot?"

    /// A small gradient, so snapshots and the self-test have a real image to use.
    static var sampleImage: Data {
        let size = 320
        let context = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
        if let context, let gradient = CGGradient(colorSpace: CGColorSpaceCreateDeviceRGB(),
                                                  colorComponents: [0.2, 0.5, 0.9, 1, 0.1, 0.2, 0.5, 1], locations: nil, count: 2) {
            context.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: size, y: size), options: [])
            if let image = context.makeImage() {
                return NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) ?? Data()
            }
        }
        return Data()
    }

    static var draftAttachments: [LoadedAttachment] { [sampleImageAttachment] }

    static var sampleImageAttachment: LoadedAttachment {
        LoadedAttachment(kind: .image, fileName: "Screenshot.png", imageData: sampleImage)
    }

    static var isRequested: Bool { ProcessInfo.processInfo.environment["APP_SEED"] == "1" && Store.isOverridden }

    static let models = [
        OllamaModel(name: "gemma4:latest", size: 9_461_576_343, capabilities: ["completion", "vision", "thinking"]),
        OllamaModel(name: "gemma4:12b-mlx", size: 7_680_999_368, capabilities: ["completion", "vision", "thinking"]),
        OllamaModel(name: "gemma4:e4b-mlx", size: 9_461_576_343, capabilities: ["completion", "vision", "thinking"]),
    ]

    private static let formattedReply = """
    ## Actors in Swift

    An **actor** protects its own state, so only one task can touch that state at a time.

    - Calls from outside use `await`.
    - Code inside the actor runs one piece at a time.

    | Type | Shared state | Data races |
    | --- | --- | --- |
    | Class | Unprotected | Possible |
    | Actor | Isolated | Prevented |

    ```swift
    actor Counter {
        private var value = 0

        func increment() -> Int {
            value += 1
            return value
        }
    }
    ```

    > Reach for an actor when several tasks share one piece of changing state.
    """

    static func insertIfRequested(into model: AppModel) {
        guard ProcessInfo.processInfo.environment["APP_SEED"] == "1" else { return }
        guard Store.isOverridden else {
            print("APP_SEED ignored: APP_STORE must be a file in /tmp")
            return
        }
        model.models = models
        model.connection = .connected
        let context = model.container.mainContext
        guard ((try? context.fetchCount(FetchDescriptor<Conversation>())) ?? 0) == 0 else { return }

        func add(_ title: String, hoursAgo: Double, reply: String, thinking: String = "", state: ReplyState = .complete, pinned: Bool = false) {
            let name = "gemma4:12b-mlx"
            let conversation = Conversation(modelName: name)
            conversation.title = ConversationTitle.make(from: title)
            conversation.isPinned = pinned
            conversation.updatedAt = .now.addingTimeInterval(-hoursAgo * 3_600)
            context.insert(conversation)
            conversation.messages.append(Message(role: .user, text: title, modelName: name, sequence: 0))
            let message = Message(role: .assistant, text: reply, modelName: name, sequence: 1, state: state)
            message.thinking = thinking
            conversation.messages.append(message)
        }

        add(attached, hoursAgo: 0.05, reply: "A blue gradient with no text or objects in it.")
        if let question = conversation(titled: attached, in: model)?.ordered.first {
            question.attachments.append(Attachment(sampleImageAttachment, sequence: 0))
        }
        add(formatted, hoursAgo: 0.1, reply: formattedReply)
        add(thinking, hoursAgo: 3,
            reply: "Yes, for one model at a time. Models around 8 GB leave room for your other apps.",
            thinking: "The person has 16 GB of memory. A model of 7.7 GB loads fully, but two at once would not fit, so the honest answer is one at a time.",
            pinned: true)
        add(writing, hoursAgo: 26, reply: "Hi Sam,\n\nCould we move our meeting to Thursday afternoon?", state: .writing)
        add(longTitle, hoursAgo: 50, reply: "The largest model writes best, and the smallest loads fastest.", state: .stopped)
        try? context.save()
    }

    static func conversation(titled text: String, in model: AppModel) -> Conversation? {
        let title = ConversationTitle.make(from: text)
        let all = (try? model.container.mainContext.fetch(FetchDescriptor<Conversation>())) ?? []
        return all.first { $0.title == title }
    }
}
