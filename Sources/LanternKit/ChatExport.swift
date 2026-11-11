import Foundation

/// A whole profile's conversations in one file, to keep safe or move to another Mac.
public struct ConversationBackup: Codable, Sendable {
    public var version = 1
    public var exportedAt: Date
    public var profileName: String
    public var conversations: [ExportedConversation]

    public init(exportedAt: Date = .now, profileName: String, conversations: [ExportedConversation]) {
        self.exportedAt = exportedAt
        self.profileName = profileName
        self.conversations = conversations
    }

    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(self)
    }

    public static func decode(_ data: Data) throws -> ConversationBackup {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(ConversationBackup.self, from: data)
    }
}

public struct ExportedConversation: Codable, Sendable, Equatable {
    public var uid: UUID
    public var title: String
    public var modelName: String
    public var createdAt: Date
    public var updatedAt: Date
    public var isPinned: Bool
    public var messages: [ExportedMessage]

    public init(uid: UUID, title: String, modelName: String, createdAt: Date, updatedAt: Date, isPinned: Bool, messages: [ExportedMessage]) {
        self.uid = uid
        self.title = title
        self.modelName = modelName
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.isPinned = isPinned
        self.messages = messages
    }
}

public struct ExportedMessage: Codable, Sendable, Equatable {
    public var uid: UUID
    /// "user" or "assistant".
    public var role: String
    public var text: String
    public var thinking: String
    public var modelName: String
    public var createdAt: Date
    public var sequence: Int
    public var state: String
    public var attachments: [ExportedAttachment]

    public init(uid: UUID, role: String, text: String, thinking: String, modelName: String, createdAt: Date,
                sequence: Int, state: String, attachments: [ExportedAttachment]) {
        self.uid = uid
        self.role = role
        self.text = text
        self.thinking = thinking
        self.modelName = modelName
        self.createdAt = createdAt
        self.sequence = sequence
        self.state = state
        self.attachments = attachments
    }
}

public struct ExportedAttachment: Codable, Sendable, Equatable {
    public var kind: String
    public var fileName: String
    public var text: String
    public var pageCount: Int
    public var durationSeconds: Double
    public var sequence: Int
    public var imageData: Data?
    public var audioData: Data?
    public var fileData: Data?

    public init(kind: String, fileName: String, text: String, pageCount: Int, durationSeconds: Double, sequence: Int,
                imageData: Data?, audioData: Data?, fileData: Data?) {
        self.kind = kind
        self.fileName = fileName
        self.text = text
        self.pageCount = pageCount
        self.durationSeconds = durationSeconds
        self.sequence = sequence
        self.imageData = imageData
        self.audioData = audioData
        self.fileData = fileData
    }
}

/// A conversation as text people can read and share.
public enum ChatExport {
    /// The conversation as Markdown: the title, then each turn under who said it.
    public static func markdown(_ conversation: ExportedConversation, displayName: (String) -> String = { $0 }) -> String {
        var lines = ["# \(conversation.title)", ""]
        for message in conversation.messages.sorted(by: { $0.sequence < $1.sequence }) {
            guard !message.text.isEmpty || !message.attachments.isEmpty else { continue }
            lines.append(message.role == "user" ? "**You**" : "**\(displayName(message.modelName))**")
            lines.append("")
            for file in message.attachments.sorted(by: { $0.sequence < $1.sequence }) {
                lines.append("*Attached: \(file.fileName)*")
            }
            if !message.attachments.isEmpty { lines.append("") }
            if !message.text.isEmpty {
                lines.append(message.text.trimmingCharacters(in: .whitespacesAndNewlines))
                lines.append("")
            }
        }
        return lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines) + "\n"
    }
}
