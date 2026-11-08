import Foundation

extension AppModel {
    var latestUserMessage: Message? {
        selectedConversation?.ordered.last { $0.role == .user }
    }

    func startEditing() {
        guard !isWriting else { return }
        editingMessageID = latestUserMessage?.uid
    }

    func cancelEditing() {
        editingMessageID = nil
        focusRequest += 1
    }

    /// Replaces the message and writes a new reply. Empty or unchanged text changes nothing.
    func saveEdit(_ message: Message, text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        editingMessageID = nil
        focusRequest += 1
        guard !trimmed.isEmpty, trimmed != message.text, !isWriting, connection == .connected,
              let conversation = message.conversation else { return }
        let installed = models.contains { $0.name == conversation.modelName }
        guard let modelName = installed ? conversation.modelName : defaultModelName else { return }
        for later in conversation.messages where later.sequence > message.sequence {
            conversation.messages.removeAll { $0.uid == later.uid }
            context.delete(later)
        }
        message.text = trimmed
        startReply(in: conversation, modelName: modelName)
    }
}
