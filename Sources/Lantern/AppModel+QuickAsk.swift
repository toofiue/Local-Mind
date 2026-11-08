import Foundation
import LanternKit

extension AppModel {
    /// Sends the Quick Ask draft without touching the main window's selection.
    @discardableResult
    func quickSend() -> Bool {
        let quick = quickAsk
        let text = quick.draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, connection == .connected else { return false }
        guard !isWriting else {
            quick.notice = "Lantern is finishing another reply."
            return false
        }
        guard let modelName = quick.conversation?.modelName ?? defaultModelName else { return false }

        let conversation: Conversation
        if let existing = quick.conversation {
            conversation = existing
        } else {
            conversation = Conversation(modelName: modelName)
            conversation.title = ConversationTitle.make(from: text)
            context.insert(conversation)
            quick.conversation = conversation
        }
        conversation.messages.append(Message(role: .user, text: text, modelName: modelName, sequence: conversation.nextSequence))
        quick.draft = ""
        quick.notice = nil
        remember(model: modelName)
        startReply(in: conversation, modelName: modelName)
        return true
    }
}
