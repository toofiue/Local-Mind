import AppKit
import LanternKit

extension AppModel {
    /// Hands the panel's conversation over to the main window.
    func openQuickAskInWindow() {
        guard let conversation = quickAsk.conversation else { return }
        QuickAskController.shared.hide()
        selection = conversation.uid
        showMainWindow()
    }

    /// Brings the main window forward, reopening it if it was closed.
    func showMainWindow() {
        NSApp.activate()
        if let window = NSApp.windows.first(where: { $0.canBecomeMain && !($0 is NSPanel) }) {
            window.makeKeyAndOrderFront(nil)
        } else {
            openMainWindow()
        }
    }

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
