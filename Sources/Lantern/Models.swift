import Foundation
import SwiftData
import LanternKit

@Model
final class Conversation {
    var uid: UUID = UUID()
    var title: String = ConversationTitle.placeholder
    var modelName: String = ""
    var createdAt: Date = Date.now
    var updatedAt: Date = Date.now
    var isPinned: Bool = false
    @Relationship(deleteRule: .cascade, inverse: \Message.conversation)
    var messages: [Message] = []

    init(modelName: String) {
        self.modelName = modelName
    }

    /// SwiftData doesn't keep relationship order.
    var ordered: [Message] { messages.sorted { $0.sequence < $1.sequence } }
    var nextSequence: Int { (messages.map(\.sequence).max() ?? -1) + 1 }
}

enum MessageRole: String {
    case user, assistant
}

enum ReplyState: String {
    case complete, writing, stopped, interrupted, failed
}

@Model
final class Message {
    var uid: UUID = UUID()
    var roleValue: String = MessageRole.user.rawValue
    var text: String = ""
    var thinking: String = ""
    var createdAt: Date = Date.now
    var modelName: String = ""
    var tokensPerSecond: Double?
    var stateValue: String = ReplyState.complete.rawValue
    var failureText: String = ""
    var sequence: Int = 0
    var conversation: Conversation?
    @Relationship(deleteRule: .cascade, inverse: \Attachment.message)
    var attachments: [Attachment] = []

    init(role: MessageRole, text: String, modelName: String, sequence: Int, state: ReplyState = .complete) {
        self.roleValue = role.rawValue
        self.text = text
        self.modelName = modelName
        self.sequence = sequence
        self.stateValue = state.rawValue
    }

    var role: MessageRole { MessageRole(rawValue: roleValue) ?? .user }
    var orderedAttachments: [Attachment] { attachments.sorted { $0.sequence < $1.sequence } }

    var state: ReplyState {
        get { ReplyState(rawValue: stateValue) ?? .complete }
        set { stateValue = newValue.rawValue }
    }
}

@Model
final class Attachment {
    var uid: UUID = UUID()
    var kindValue: String = AttachmentKind.text.rawValue
    var fileName: String = ""
    @Attribute(.externalStorage) var imageData: Data?
    var text: String = ""
    var pageCount: Int = 0
    var sequence: Int = 0
    var message: Message?

    init(_ loaded: LoadedAttachment, sequence: Int) {
        self.kindValue = loaded.kind.rawValue
        self.fileName = loaded.fileName
        self.imageData = loaded.imageData
        self.text = loaded.text
        self.pageCount = loaded.pageCount
        self.sequence = sequence
    }

    var kind: AttachmentKind { AttachmentKind(rawValue: kindValue) ?? .text }
}

/// One finished Model Lab run. The report is stored whole, as JSON.
@Model
final class ModelTestRun {
    var uid: UUID = UUID()
    var modelName: String = ""
    var date: Date = Date.now
    var payload: Data = Data()

    init(modelName: String, date: Date, payload: Data) {
        self.modelName = modelName
        self.date = date
        self.payload = payload
    }
}
