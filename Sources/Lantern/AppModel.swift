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
    @Published private(set) var canEdit = false
    @Published var quickAskHotkey = Hotkey.standard

    func update(isWriting: Bool, hasReply: Bool, hasSelection: Bool, isPinned: Bool, canDelete: Bool, canEdit: Bool) {
        if self.canEdit != canEdit { self.canEdit = canEdit }
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
            showingModels = false
            labModelName = nil
            selectedConversation = conversation(with: selection)
            syncMenu()
            focusRequest += 1
        }
    }
    private(set) var selectedConversation: Conversation?

    var connection: Connection = .connecting
    var models: [OllamaModel] = []
    /// The models in memory right now.
    var loaded: [LoadedModel] = []
    /// True while the detail area shows the Models page.
    var showingModels = false
    var draftModelName: String?
    let replies = ReplyWriter()
    let quickAsk = QuickAskState()
    let lab = ModelLabRunner()
    let benchmark = BenchmarkRunner()
    let benchmarkLibrary = BenchmarkLibrary()
    var benchmarkReports: [String: BenchmarkReport] = [:]
    /// Models still waiting their turn in Test All Models.
    var labQueue: [String] = []
    /// Which tab the Test page is showing.
    var labTab: LabTab = .quickCheck
    var isDownloadingBenchmarks = false
    var benchmarkDownloadFailed = false
    /// The model whose Lab page is open.
    var labModelName: String?
    /// The latest Lab report for each model, once read.
    var labReports: [String: LabReport] = [:]
    /// Reopens the main window after it was closed.
    @ObservationIgnored var openMainWindow: () -> Void = {}
    /// The window can reopen, but connecting and launch repair run once.
    @ObservationIgnored var hasStarted = false
    var showingModelPicker = false
    /// The conversation whose sidebar row is being edited.
    var renamingID: UUID?
    /// The message being changed in place.
    var editingMessageID: UUID?
    /// The conversation waiting on a delete confirmation.
    var pendingDeletion: Conversation?
    var searchText = ""
    /// Files attached to the message being written.
    var draftAttachments: [LoadedAttachment] = []
    /// Why the last attachment couldn't be added. It clears itself after a few seconds.
    var attachmentNotice: String? {
        didSet { clearNoticeLater() }
    }
    @ObservationIgnored var noticeDuration: Duration = .seconds(4)
    @ObservationIgnored private var noticeTask: Task<Void, Never>?
    /// Goes up whenever the search field should take focus.
    var searchRequest = 0
    /// Goes up whenever the message field should take focus.
    var focusRequest = 0
    /// Text a welcome-screen starter puts in the message field.
    var prefill: String?
    /// The system-wide shortcut for Quick Ask. Test and snapshot runs leave it alone.
    var hotkey: Hotkey = AppModel.savedHotkey {
        didSet {
            MenuState.shared.quickAskHotkey = hotkey
            if !Store.isOverridden, let data = try? JSONEncoder().encode(hotkey) {
                UserDefaults.standard.set(data, forKey: "quickAskHotkey")
            }
        }
    }
    /// Why the last shortcut couldn't be used.
    var hotkeyMessage: String?
    /// Names you've given models, by their Ollama name. Test and snapshot runs leave them alone.
    var modelNicknames: [String: String] = AppModel.savedNicknames {
        didSet { if !Store.isOverridden { UserDefaults.standard.set(modelNicknames, forKey: "modelNicknames") } }
    }
    /// Why the last message is waiting: its model won't fit comfortably.
    var memoryWarning: MemoryWarning?
    @ObservationIgnored var readMemory: () -> MemorySnapshot = { SystemMonitor.memory() }
    @ObservationIgnored var readTopApps: () -> [SystemMonitor.AppMemory] = { SystemMonitor.topApps() }
    /// The model chosen in Settings. Empty means the last one used.
    var chosenDefaultModel: String = UserDefaults.standard.string(forKey: "defaultModel") ?? "" {
        didSet { if !Store.isOverridden { UserDefaults.standard.set(chosenDefaultModel, forKey: "defaultModel") } }
    }
    /// How long a model stays in memory after its last reply. Test and snapshot runs leave it alone.
    var keepLoadedMinutes: Int = {
        let stored = UserDefaults.standard.integer(forKey: "keepLoadedMinutes")
        return stored > 0 ? stored : 5
    }() {
        didSet { if !Store.isOverridden { UserDefaults.standard.set(keepLoadedMinutes, forKey: "keepLoadedMinutes") } }
    }
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
        MenuState.shared.quickAskHotkey = hotkey
        replies.onChange = { [weak self] in self?.syncMenu() }
        lab.onStateChange = { [weak self] in
            guard let self else { return }
            self.syncMenu()
            Task { await self.refreshLoaded() }
            // Test All Models: when one model finishes, start the next.
            if !self.lab.isRunning, !self.labQueue.isEmpty {
                let next = self.labQueue.removeFirst()
                Task { self.runLab(next, skipMemoryCheck: true) }
            }
        }
        lab.onFinished = { [weak self] report in self?.saveLabReport(report) }
        benchmark.onStateChange = { [weak self] in
            self?.syncMenu()
            Task { await self?.refreshLoaded() }
        }
        benchmark.onFinished = { [weak self] report in self?.saveBenchmarkReport(report) }
        replies.onFinished = { [weak self] lostConnection in
            guard let self else { return }
            if lostConnection, !(await self.refreshModels()) { self.connection = .failed }
            self.syncMenu()
            self.focusRequest += 1
            await self.refreshLoaded()
        }
    }

    var context: ModelContext { container.mainContext }

    /// Each new notice gets its full time on screen before it clears.
    private func clearNoticeLater() {
        noticeTask?.cancel()
        guard let shown = attachmentNotice else { return }
        noticeTask = Task { [weak self] in
            try? await Task.sleep(for: self?.noticeDuration ?? .seconds(4))
            guard !Task.isCancelled, let self, self.attachmentNotice == shown else { return }
            self.attachmentNotice = nil
        }
    }

    private static var savedNicknames: [String: String] {
        guard !Store.isOverridden else { return [:] }
        return UserDefaults.standard.dictionary(forKey: "modelNicknames") as? [String: String] ?? [:]
    }

    /// The name to show for a model: yours if you've set one.
    func displayName(_ model: String) -> String {
        modelNicknames[model] ?? model
    }

    /// An empty name restores the original.
    func setNickname(_ nickname: String, for model: String) {
        let trimmed = nickname.trimmingCharacters(in: .whitespacesAndNewlines)
        modelNicknames[model] = trimmed.isEmpty || trimmed == model ? nil : trimmed
    }

    private static var savedHotkey: Hotkey {
        guard let data = UserDefaults.standard.data(forKey: "quickAskHotkey"),
              let saved = try? JSONDecoder().decode(Hotkey.self, from: data) else { return .standard }
        return saved
    }

    /// Switches the shortcut, or says why it can't be used and keeps the old one.
    func changeHotkey(_ new: Hotkey) {
        hotkeyMessage = nil
        guard new != hotkey else { return }
        guard new.hasRequiredModifier else {
            hotkeyMessage = "Include ⌘, ⌃, or ⌥ in the shortcut."
            return
        }
        guard !GlobalHotKey.isReservedBySystem(new) else {
            hotkeyMessage = "macOS already uses that shortcut. Choose another."
            return
        }
        guard GlobalHotKey.shared.register(new) else {
            hotkeyMessage = "Another app already uses that shortcut. Choose another."
            return
        }
        hotkey = new
    }

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

    /// Picks up models installed or removed while Lantern was in the background.
    func refreshInstalledModels() async {
        guard connection == .connected else { return }
        _ = await refreshModels()
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
        let candidates = [selectedConversation?.modelName, draftModelName]
        if let name = candidates.compactMap({ $0 }).first(where: installed.contains) { return name }
        return defaultModelName ?? selectedConversation?.modelName
    }

    /// What a new conversation starts with: the last model used, or the
    /// smallest, which is the safest fit in memory.
    var defaultModelName: String? {
        let remembered = Store.isOverridden ? nil : UserDefaults.standard.string(forKey: "lastModel")
        return DefaultModel.resolve(chosen: chosenDefaultModel, remembered: remembered, installed: models)
    }

    func chooseModel(_ name: String) {
        memoryWarning = nil
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

    func remember(model name: String) {
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
        labModelName = nil
        draftModelName = nil
        showingModels = false
    }

    func showModels() {
        // Clearing the selection lets a click on any conversation come back from this page.
        selection = nil
        labModelName = nil
        showingModels = true
    }

    /// A model can't be unloaded while it's writing a reply.
    func canUnload(_ name: String) -> Bool {
        replies.activeModelName != name && lab.modelName != name && benchmark.modelName != name
    }

    func unload(_ name: String) async {
        guard canUnload(name) else { return }
        try? await client.unload(name)
        await refreshLoaded()
    }

    func refreshLoaded() async {
        if let current = try? await client.loadedModels() { loaded = current }
    }

    /// Keeps the loaded state current for the Models page and the menu bar.
    func monitorLoadedModels() async {
        while !Task.isCancelled {
            await refreshLoaded()
            try? await Task.sleep(for: showingModels ? .seconds(2) : .seconds(5))
        }
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

    /// True while a reply or a Lab run is using the model. Only one can at a time.
    var isWriting: Bool { replies.isWriting || lab.isRunning || benchmark.isRunning }

    /// Returns false when the message couldn't be sent, so the field keeps its text.
    @discardableResult
    func send(_ raw: String, skipMemoryCheck: Bool = false) -> Bool {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isWriting, connection == .connected, let modelName = currentModelName else { return false }
        if draftAttachments.contains(where: { $0.kind == .image }), let refusal = imageRefusal {
            attachmentNotice = refusal
            return false
        }
        if draftAttachments.contains(where: { $0.kind == .audio }), let refusal = audioRefusal {
            attachmentNotice = refusal
            return false
        }

        if !skipMemoryCheck, let warning = memoryWarningIfNeeded(for: modelName, surface: .main) {
            memoryWarning = warning
            return false
        }
        memoryWarning = nil

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
    func retry(_ target: Conversation? = nil) {
        guard !isWriting, connection == .connected, let conversation = target ?? selectedConversation,
              let reply = conversation.ordered.last(where: { $0.role == .assistant }) else { return }
        let installed = models.contains { $0.name == conversation.modelName }
        guard let modelName = installed ? conversation.modelName : defaultModelName else { return }
        conversation.messages.removeAll { $0.uid == reply.uid }
        context.delete(reply)
        startReply(in: conversation, modelName: modelName)
    }

    func stop() {
        replies.stop()
        labQueue = []
        lab.stop()
        benchmark.stop()
    }

    func copyLatestReply() {
        if let text = latestReply?.text, !text.isEmpty { Clipboard.copy(text) }
    }

    /// Lets the self-test wait for a reply to finish.
    func waitForReply() async {
        await replies.wait()
    }

    func startReply(in conversation: Conversation, modelName: String) {
        let turns = ChatHistory.turns(conversation.ordered.map(turn(for:)))
        let reply = Message(role: .assistant, text: "", modelName: modelName,
                            sequence: conversation.nextSequence, state: .writing)
        conversation.messages.append(reply)
        conversation.updatedAt = .now
        save()

        let think = models.first { $0.name == modelName }?.supportsThinking ?? false
        replies.start(reply, in: conversation, modelName: modelName, turns: turns, think: think, keepAlive: "\(keepLoadedMinutes)m", client: client)
    }

    func save() {
        try? context.save()
        syncMenu()
    }

    func syncMenu() {
        MenuState.shared.update(isWriting: isWriting,
                                hasReply: !(latestReply?.text.isEmpty ?? true),
                                hasSelection: selectedConversation != nil,
                                isPinned: selectedConversation?.isPinned ?? false,
                                canDelete: selectedConversation.map { !isWriting(in: $0) } ?? false,
                                canEdit: !isWriting && latestUserMessage != nil)
    }
}

enum Clipboard {
    static func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}
