import AppKit
import Combine
import Foundation
import SwiftData
import LanternKit

enum Connection: Equatable {
    case connecting, starting, connected, failed
}

/// Menus don't observe `@Observable` models, so the App observes this instead.
final class MenuState: ObservableObject {
    static let shared = MenuState()
    @Published private(set) var isWriting = false
    @Published private(set) var hasReply = false
    @Published private(set) var hasSelection = false
    @Published private(set) var isPinned = false
    @Published private(set) var canDelete = false

    func update(isWriting: Bool, hasReply: Bool, hasSelection: Bool, isPinned: Bool, canDelete: Bool) {
        if self.canDelete != canDelete { self.canDelete = canDelete }
        if self.isPinned != isPinned { self.isPinned = isPinned }
        if self.isWriting != isWriting { self.isWriting = isWriting }
        if self.hasReply != hasReply { self.hasReply = hasReply }
        if self.hasSelection != hasSelection { self.hasSelection = hasSelection }
    }
}

/// App-wide state that menus, toolbars, and views share.
@Observable
final class AppModel {
    let container: ModelContainer
    var client: OllamaClient

    /// nil means a new conversation that isn't saved yet.
    var selection: UUID? {
        didSet {
            selectedConversation = conversation(with: selection)
            syncMenu()
            focusRequest += 1
        }
    }
    private(set) var selectedConversation: Conversation?

    var connection: Connection = .connecting
    var models: [OllamaModel] = []
    var draftModelName: String?
    let replies = ReplyWriter()
    var showingModelPicker = false
    /// The conversation whose sidebar row is being edited.
    var renamingID: UUID?
    /// The conversation waiting on a delete confirmation.
    var pendingDeletion: Conversation?
    var searchText = ""
    /// Files attached to the message being written.
    var draftAttachments: [LoadedAttachment] = []
    /// Why the last attachment couldn't be added.
    var attachmentNotice: String?
    /// Goes up whenever the search field should take focus.
    var searchRequest = 0
    /// Goes up whenever the message field should take focus.
    var focusRequest = 0
    /// Settings reopens on the last tab. Test and snapshot runs leave it alone.
    var settingsTab: SettingsTab = SettingsTab(rawValue: UserDefaults.standard.string(forKey: "settings.tab") ?? "") ?? .appearance {
        didSet { if !Store.isOverridden { UserDefaults.standard.set(settingsTab.rawValue, forKey: "settings.tab") } }
    }

    @ObservationIgnored var startOllama: @MainActor () -> Void = { AppModel.openOllamaApp() }
    @ObservationIgnored var startupWait: Duration = .seconds(15)

    init(container: ModelContainer) {
        self.container = container
        var base = OllamaClient.defaultBase
        if Store.isOverridden, let value = ProcessInfo.processInfo.environment["APP_OLLAMA_URL"], let url = URL(string: value) {
            base = url
        }
        client = OllamaClient(base: base)
        replies.onChange = { [weak self] in self?.syncMenu() }
        replies.onFinished = { [weak self] lostConnection in
            guard let self else { return }
            if lostConnection, !(await self.refreshModels()) { self.connection = .failed }
            self.syncMenu()
            self.focusRequest += 1
        }
    }

    private var context: ModelContext { container.mainContext }

    // MARK: Connection

    func connect() async {
        connection = .connecting
        if await refreshModels() {
            finishConnecting()
            return
        }
        connection = .starting
        startOllama()
        let deadline = ContinuousClock.now + startupWait
        while ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(500))
            if await refreshModels() {
                finishConnecting()
                return
            }
        }
        connection = .failed
    }

    private func finishConnecting() {
        connection = .connected
        focusRequest += 1
    }

    private func refreshModels() async -> Bool {
        guard let installed = try? await client.models() else { return false }
        models = installed
        return true
    }

    private static func openOllamaApp() {
        let url = URL(fileURLWithPath: "/Applications/Ollama.app")
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        configuration.hides = true
        NSWorkspace.shared.openApplication(at: url, configuration: configuration)
    }

    /// A reply still marked as writing after a launch was cut off when the app quit.
    func repairInterruptedReplies() {
        let writing = ReplyState.writing.rawValue
        let stale = (try? context.fetch(FetchDescriptor<Message>(predicate: #Predicate { $0.stateValue == writing }))) ?? []
        for message in stale { message.state = .interrupted }
        save()
    }

    // MARK: Models

    var currentModelName: String? {
        let installed = Set(models.map(\.name))
        let remembered = Store.isOverridden ? nil : UserDefaults.standard.string(forKey: "lastModel")
        let candidates = [selectedConversation?.modelName, draftModelName, remembered]
        if let name = candidates.compactMap({ $0 }).first(where: installed.contains) { return name }
        // With nothing to go on, the smallest model is the safest fit in memory.
        return models.min { $0.size < $1.size }?.name ?? selectedConversation?.modelName
    }

    func chooseModel(_ name: String) {
        if let selectedConversation {
            selectedConversation.modelName = name
            save()
        } else {
            draftModelName = name
        }
        remember(model: name)
        showingModelPicker = false
        focusRequest += 1
    }

    private func remember(model name: String) {
        if !Store.isOverridden { UserDefaults.standard.set(name, forKey: "lastModel") }
    }

    // MARK: Conversations

    private func conversation(with uid: UUID?) -> Conversation? {
        guard let uid else { return nil }
        var descriptor = FetchDescriptor<Conversation>(predicate: #Predicate { $0.uid == uid })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    func newConversation() {
        selection = nil
    }

    func togglePin(_ conversation: Conversation? = nil) {
        guard let target = conversation ?? selectedConversation else { return }
        target.isPinned.toggle()
        save()
    }

    func isWriting(in conversation: Conversation) -> Bool {
        replies.isWriting(in: conversation)
    }

    /// Asks for confirmation. A reply can't be deleted while it's being written.
    func requestDelete(_ conversation: Conversation? = nil) {
        guard let target = conversation ?? selectedConversation, !isWriting(in: target) else { return }
        pendingDeletion = target
    }

    func delete(_ conversation: Conversation) {
        pendingDeletion = nil
        guard !isWriting(in: conversation) else { return }
        let all = (try? context.fetch(FetchDescriptor<Conversation>())) ?? []
        let groups = ConversationGroups.split(all, isPinned: \.isPinned, updatedAt: \.updatedAt)
        let order = (groups.pinned + groups.recent).map(\.uid)
        let wasSelected = selection == conversation.uid
        let next = ConversationGroups.next(in: order, afterRemoving: conversation.uid)
        // Move away first, so nothing on screen is reading the deleted conversation.
        if wasSelected { selection = next }
        context.delete(conversation)
        save()
    }

    func startRenaming(_ conversation: Conversation? = nil) {
        renamingID = (conversation ?? selectedConversation)?.uid
    }

    /// An empty title keeps the old one.
    func rename(_ conversation: Conversation, to title: String) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            conversation.title = trimmed
            save()
        }
        finishRenaming()
    }

    func finishRenaming() {
        guard renamingID != nil else { return }
        renamingID = nil
        focusRequest += 1
    }

    var latestReply: Message? {
        selectedConversation?.ordered.last { $0.role == .assistant }
    }

    var isWriting: Bool { replies.isWriting }

    /// Returns false when the message couldn't be sent, so the field keeps its text.
    @discardableResult
    func send(_ raw: String) -> Bool {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isWriting, connection == .connected, let modelName = currentModelName else { return false }
        if draftAttachments.contains(where: { $0.kind == .image }), let refusal = imageRefusal {
            attachmentNotice = refusal
            return false
        }

        let conversation: Conversation
        if let selectedConversation {
            conversation = selectedConversation
            conversation.modelName = modelName
        } else {
            conversation = Conversation(modelName: modelName)
            conversation.title = ConversationTitle.make(from: text)
            context.insert(conversation)
            selection = conversation.uid
        }
        let message = Message(role: .user, text: text, modelName: modelName, sequence: conversation.nextSequence)
        conversation.messages.append(message)
        for (index, loaded) in draftAttachments.enumerated() {
            message.attachments.append(Attachment(loaded, sequence: index))
        }
        draftAttachments = []
        attachmentNotice = nil
        remember(model: modelName)
        startReply(in: conversation, modelName: modelName)
        return true
    }

    /// Replaces the latest reply with a new one.
    func retry() {
        guard !isWriting, connection == .connected,
              let conversation = selectedConversation, let reply = latestReply,
              let modelName = currentModelName else { return }
        conversation.messages.removeAll { $0.uid == reply.uid }
        context.delete(reply)
        startReply(in: conversation, modelName: modelName)
    }

    func stop() {
        replies.stop()
    }

    func copyLatestReply() {
        if let text = latestReply?.text, !text.isEmpty { Clipboard.copy(text) }
    }

    /// Lets the self-test wait for a reply to finish.
    func waitForReply() async {
        await replies.wait()
    }

    private func startReply(in conversation: Conversation, modelName: String) {
        let turns = ChatHistory.turns(conversation.ordered.map(turn(for:)))
        let reply = Message(role: .assistant, text: "", modelName: modelName,
                            sequence: conversation.nextSequence, state: .writing)
        conversation.messages.append(reply)
        conversation.updatedAt = .now
        save()

        let think = models.first { $0.name == modelName }?.supportsThinking ?? false
        replies.start(reply, in: conversation, modelName: modelName, turns: turns, think: think, client: client)
    }

    private func save() {
        try? context.save()
        syncMenu()
    }

    private func syncMenu() {
        MenuState.shared.update(isWriting: replies.isWriting,
                                hasReply: !(latestReply?.text.isEmpty ?? true),
                                hasSelection: selectedConversation != nil,
                                isPinned: selectedConversation?.isPinned ?? false,
                                canDelete: selectedConversation.map { !isWriting(in: $0) } ?? false)
    }
}

enum Clipboard {
    static func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}
