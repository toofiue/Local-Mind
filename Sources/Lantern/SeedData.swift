import AppKit
import CoreText
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

    static var sampleBenchmarkReport: BenchmarkReport {
        func suite(_ suite: BenchmarkSuite, _ passed: Int, _ failed: Int) -> BenchmarkSuiteResult {
            let right = (0..<passed).map { BenchmarkItemResult(id: "\(suite.rawValue)-\($0)", passed: true, reply: "") }
            let wrong = (0..<failed).map { BenchmarkItemResult(id: "\(suite.rawValue)-x\($0)", passed: false, reply: "The answer is 41.", detail: "Expected 42") }
            return BenchmarkSuiteResult(suite: suite, items: right + wrong, planned: passed + failed)
        }
        return BenchmarkReport(modelName: "gemma4:12b-mlx", date: .now, seconds: 900, size: .sample50, wasStopped: false,
                               suites: [suite(.gsm8k, 43, 7), suite(.ifeval, 36, 14)])
    }

    static var sampleLabReport: LabReport {
        func row(_ id: String, _ area: LabArea, _ name: String, _ prompt: String, _ expected: String, _ reply: String, _ passed: Bool, _ tokens: Int? = nil) -> LabCaseResult {
            LabCaseResult(id: id, area: area, name: name, reply: reply, passed: passed, documentTokens: tokens, prompt: prompt, expected: expected)
        }
        return LabReport(modelName: "gemma4:12b-mlx", date: .now, tokensPerSecond: 27, loadSeconds: 3, memoryBytes: 7_700_000_000,
                         swapGrowthBytes: 0, totalMemoryBytes: 17_179_869_184, supportsImages: true, supportsTools: true, results: [
                            row("speed", .speed, "Write a paragraph", "Write one short paragraph about the ocean.", "Any complete reply.", "The ocean is a vast, shimmering expanse.", true),
                            row("r-1", .reasoning, "Trick question", "A farmer has 17 sheep. All but 9 run away. How many are left?", "9", "9", true),
                            row("r-2", .reasoning, "Arithmetic", "What is 37 times 43?", "1591", "1591", true),
                            row("c-1", .code, "Read Python", "print(sum(i * i for i in range(4)))", "14", "14", true),
                            row("c-2", .code, "Read string slicing", "print(\"lantern\"[::-1][:3])", "nre", "nret", false),
                            row("i-1", .instructions, "Exact format", "List three fruits as exactly three lines.", "Exactly three lines", "- Apple", true),
                            row("d-1", .data, "Extract to JSON", "Mira is 34 years old.", "Valid JSON", "{\"name\": \"Mira\", \"age\": 34}", true),
                            row("doc-1", .documents, "20,000 tokens", "A 20,000-token document with three hidden facts.", "7741, harbor, and marigold", "7741, harbor, marigold", true, 20_000),
                            row("img-1", .images, "See a color", "What color is the square?", "Red", "Red", true),
                            row("tool-1", .tools, "Call a tool", "What's the weather in Paris?", "A call to get_weather with Paris", "Called get_weather (city: Paris)", true),
                         ])
    }

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

    static var draftAttachments: [LoadedAttachment] {
        [sampleImageAttachment,
         LoadedAttachment(kind: .pdf, fileName: "Quarterly report.pdf", text: "Revenue rose in the third quarter.", pageCount: 12),
         LoadedAttachment(kind: .audio, fileName: "Voice note.m4a", audioData: Data(count: 64), durationSeconds: 83)]
    }

    /// A one-page PDF, with text or with none, for the self-test.
    static func samplePDF(text: String) -> Data {
        let output = NSMutableData()
        var box = CGRect(x: 0, y: 0, width: 300, height: 300)
        guard let consumer = CGDataConsumer(data: output),
              let context = CGContext(consumer: consumer, mediaBox: &box, nil) else { return Data() }
        context.beginPDFPage(nil)
        if !text.isEmpty {
            let font = CTFontCreateWithName("Helvetica" as CFString, 12, nil)
            let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: [.font: font]))
            context.textPosition = CGPoint(x: 20, y: 200)
            CTLineDraw(line, context)
        }
        context.endPDFPage()
        context.closePDF()
        return output as Data
    }

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
        model.loaded = [LoadedModel(name: "gemma4:12b-mlx", memory: 7_680_999_368)]
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
            if state == .complete { message.tokensPerSecond = 28 }
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
