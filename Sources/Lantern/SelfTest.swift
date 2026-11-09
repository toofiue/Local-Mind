import AppKit
import Carbon.HIToolbox
import SwiftData
import LanternKit

/// Self-test for agents: runs the app's real functions on a test store,
/// prints PASS or FAIL per check, and quits with exit code 0 or 1.
///   APP_STORE=/tmp/Lantern-self.store ~/Applications/Lantern.app/Contents/MacOS/Lantern --selftest
/// (tools/selftest.sh does this.) Ollama is replaced by a script, so no model
/// loads. APP_SELFTEST_LIVE=<model> adds one real reply through local Ollama.
@MainActor
enum SelfTest {
    static var requested: Bool { CommandLine.arguments.contains("--selftest") }
    /// Read by AppDelegate.applicationWillTerminate.
    static var exitCode: Int32 = 0
    private static var failures = 0
    private static var count = 0

    static func runIfRequested(model: AppModel) {
        guard requested else { return }
        // Print each line at once, so a crash keeps the lines before it.
        setvbuf(stdout, nil, _IOLBF, 0)
        guard Store.isOverridden else {
            print("SELFTEST refused: set APP_STORE to a file in /tmp")
            finish(code: 1)
            return
        }
        Task {
            try? await Task.sleep(for: .seconds(0.5))
            await runScripted(model)
            if let live = ProcessInfo.processInfo.environment["APP_SELFTEST_LIVE"], !live.isEmpty {
                await runLive(model, modelName: live)
            }
            print(failures == 0 ? "SELFTEST PASS \(count) checks" : "SELFTEST FAIL \(failures) of \(count) checks")
            finish(code: failures == 0 ? 0 : 1)
        }
    }

    private static func runScripted(_ model: AppModel) async {
        let first = OllamaModel(name: "first:1", size: 100, capabilities: ["completion", "thinking", "vision"], contextLimit: 100)
        let second = OllamaModel(name: "second:1", size: 200, capabilities: ["completion"])
        let transport = ScriptedTransport(installed: [first, second])
        model.client = OllamaClient(transport: transport)
        model.startOllama = {}
        model.readMemory = { MemorySnapshot(totalBytes: 68_719_476_736, availableBytes: 34_359_738_368) }
        model.readTopApps = { [] }
        model.startupWait = .milliseconds(600)

        // S-001 connecting
        await model.connect()
        check("S-001 connects and lists models", model.connection == .connected && model.models.count == 2)
        check("S-001 a model is chosen", model.currentModelName == "first:1")

        // S-003 and S-010 sending
        transport.script(ScriptedTransport.reply(thinking: ["Let me ", "think"], text: ["Hello ", "there"]))
        check("S-003 a blank message is refused", !model.send("   \n"))
        check("S-003 a message is accepted", model.send("  Fix my code\nplease "))
        await model.waitForReply()
        let conversation = model.selectedConversation
        check("S-005 the new conversation is selected", conversation != nil)
        check("S-011 the title comes from the first line", conversation?.title == "Fix my code")
        let reply = model.latestReply
        check("S-003 the reply has its text", reply?.text == "Hello there", reply?.text ?? "nil")
        check("S-010 thinking is kept apart", reply?.thinking == "Let me think", reply?.thinking ?? "nil")
        check("S-003 the reply finishes", reply?.state == .complete)
        check("S-033 speed is saved", reply?.tokensPerSecond == 20)
        check("S-006 the reply names its model", reply?.modelName == "first:1")
        check("S-010 a thinking model gets the think option", transport.chatBodies.last?.contains("\"think\":true") == true)
        check("writing has ended", !model.isWriting)

        // S-003 history
        transport.script(ScriptedTransport.reply(text: ["Second"]))
        model.send("And again")
        await model.waitForReply()
        let body = transport.chatBodies.last ?? ""
        let order = ["Fix my code", "Hello there", "And again"].compactMap { body.range(of: $0)?.lowerBound }
        check("S-003 history goes in order", order.count == 3 && order == order.sorted(), body)

        // S-006 switching
        transport.setLoaded(["first:1"])
        model.chooseModel("second:1")
        transport.script(ScriptedTransport.reply(text: ["From second"]))
        model.send("Switch")
        await model.waitForReply()
        let paths = transport.requests.map(\.path)
        let unload = paths.lastIndex { $0.hasSuffix("/api/generate") }
        let chat = paths.lastIndex { $0.hasSuffix("/api/chat") }
        check("S-006 the old model unloads before the next loads", unload != nil && chat != nil && unload! < chat!)
        check("S-006 the conversation remembers its model", model.selectedConversation?.modelName == "second:1")
        check("S-006 the older reply keeps its model", model.selectedConversation?.ordered[1].modelName == "first:1")
        check("S-010 other models don't get the think option", transport.chatBodies.last?.contains("think") == false)

        // S-004 stop
        transport.script(ScriptedTransport.reply(text: Array(repeating: "word ", count: 200)), delay: .milliseconds(20))
        model.send("Long one")
        try? await Task.sleep(for: .milliseconds(300))
        check("S-004 Stop is available while writing", model.isWriting)
        let started = ContinuousClock.now
        model.stop()
        await model.waitForReply()
        check("S-004 stops within a second", ContinuousClock.now - started < .seconds(1))
        let stopped = model.latestReply
        check("S-004 the reply is marked stopped", stopped?.state == .stopped)
        let partial = stopped?.text.count ?? 0
        check("S-004 the text so far stays", partial > 0 && partial < 1_000, "\(partial)")

        // S-024 retry
        let stoppedID = stopped?.uid
        let replies = model.selectedConversation?.messages.count ?? 0
        transport.script(ScriptedTransport.reply(text: ["Retried"]))
        model.retry()
        await model.waitForReply()
        check("S-024 Retry replaces the reply", model.latestReply?.text == "Retried" && model.latestReply?.uid != stoppedID)
        check("S-024 no extra message appears", model.selectedConversation?.messages.count == replies)

        // S-006 load failure
        transport.script([#"{"error":"model requires more system memory"}"#])
        model.send("Too big")
        await model.waitForReply()
        check("S-006 a failed load explains itself", model.latestReply?.failureText.contains("Unable to load second:1") == true)

        // S-002 lost connection
        transport.script([#"{"message":{"role":"assistant","content":"Half a"},"done":false}"#])
        model.send("Drop this")
        await model.waitForReply()
        check("S-002 a dropped reply keeps its text", model.latestReply?.text == "Half a")
        check("S-002 a dropped reply is marked interrupted", model.latestReply?.state == .interrupted)

        transport.setDown(true)
        await model.connect()
        check("S-002 an unreachable Ollama fails", model.connection == .failed)
        check("S-002 sending is refused while offline", !model.send("nope"))
        transport.setDown(false)
        await model.connect()
        check("S-002 Try Again reconnects", model.connection == .connected)

        // S-005 persistence
        let uid = model.selectedConversation?.uid
        let messageCount = model.selectedConversation?.messages.count ?? 0
        let reopened = try? ModelContainer(for: Conversation.self, Message.self, Attachment.self, ModelTestRun.self,
                                           configurations: ModelConfiguration(url: Store.url))
        let saved = (try? reopened?.mainContext.fetch(FetchDescriptor<Conversation>())) ?? []
        let found = saved.first { $0.uid == uid }
        check("S-005 conversations survive reopening the store", found?.messages.count == messageCount, "\(found?.messages.count ?? -1)")

        model.newConversation()
        check("S-005 New Conversation clears the selection", model.selectedConversation == nil)
        model.selection = uid
        check("S-005 selecting brings it back", model.selectedConversation?.uid == uid)

        // S-012 rename
        if let conversation = model.selectedConversation {
            let original = conversation.title
            model.startRenaming()
            check("S-012 Rename edits the selected row", model.renamingID == conversation.uid)
            model.rename(conversation, to: "   ")
            check("S-012 an empty title keeps the old one", conversation.title == original)
            model.startRenaming(conversation)
            model.finishRenaming()
            check("S-012 Escape leaves the title and ends editing", conversation.title == original && model.renamingID == nil)
            model.rename(conversation, to: "  My Title ")
            check("S-012 a new title is saved, trimmed", conversation.title == "My Title")
            transport.script(ScriptedTransport.reply(text: ["Fine"]))
            model.send("One more message")
            await model.waitForReply()
            check("S-012 a title you set stays after more messages", conversation.title == "My Title")
        }

        // S-013 pin
        if let conversation = model.selectedConversation {
            let date = conversation.updatedAt
            model.togglePin()
            check("S-013 Pin marks the conversation", conversation.isPinned)
            check("S-013 the menu knows it's pinned", MenuState.shared.isPinned)
            check("S-013 pinning leaves its date alone", conversation.updatedAt == date)
            model.togglePin(conversation)
            check("S-013 Unpin clears it", !conversation.isPinned && !MenuState.shared.isPinned)
        }

        // S-014 delete
        do {
            let context = model.container.mainContext
            func messageCount() -> Int { (try? context.fetchCount(FetchDescriptor<Message>())) ?? -1 }
            func conversationCount() -> Int { (try? context.fetchCount(FetchDescriptor<Conversation>())) ?? -1 }
            func start(_ text: String) async -> Conversation? {
                model.newConversation()
                transport.script(ScriptedTransport.reply(text: ["Reply"]))
                model.send(text)
                await model.waitForReply()
                // Separate timestamps, so the order is certain.
                try? await Task.sleep(for: .milliseconds(20))
                return model.selectedConversation
            }
            let oldest = await start("Delete oldest")
            let middle = await start("Delete middle")
            let newest = await start("Delete newest")
            guard let oldest, let middle, let newest else { return check("S-014 setup", false) }

            model.selection = middle.uid
            let conversations = conversationCount()
            let messages = messageCount()
            model.requestDelete()
            check("S-014 Delete asks first", model.pendingDeletion?.uid == middle.uid && conversationCount() == conversations)
            model.pendingDeletion = nil
            check("S-014 Cancel keeps it", conversationCount() == conversations)
            model.delete(middle)
            check("S-014 the conversation is gone", conversationCount() == conversations - 1)
            check("S-014 its messages are gone too", messageCount() == messages - 2, "\(messageCount())")
            check("S-014 the next row is selected", model.selection == oldest.uid)

            let current = model.selection
            model.delete(newest)
            check("S-014 deleting another row keeps your selection", model.selection == current)

            transport.script(ScriptedTransport.reply(text: Array(repeating: "x ", count: 100)), delay: .milliseconds(20))
            model.send("Writing now")
            try? await Task.sleep(for: .milliseconds(150))
            model.requestDelete()
            check("S-014 a conversation being written can't be deleted", model.pendingDeletion == nil)
            model.delete(oldest)
            check("S-014 and direct deletion is refused too", model.selection == oldest.uid)
            model.stop()
            await model.waitForReply()
        }

        // S-016 images
        do {
            model.newConversation()
            await model.addPastedImage(SeedData.sampleImage)
            check("S-016 a pasted image attaches", model.draftAttachments.first?.kind == .image)
            check("S-016 a pasted image gets a name", model.draftAttachments.first?.fileName == "Pasted Image")
            transport.script(ScriptedTransport.reply(text: ["A gradient"]))
            model.send("What is this?")
            await model.waitForReply()
            check("S-016 the image goes in the request", transport.chatBodies.last?.contains("\"images\":[\"") == true)
            check("S-016 sending clears the draft", model.draftAttachments.isEmpty)
            let question = model.selectedConversation?.ordered.first
            check("S-016 the image is stored with its message", question?.attachments.first?.imageData?.isEmpty == false)

            let reopened = try? ModelContainer(for: Conversation.self, Message.self, Attachment.self, ModelTestRun.self,
                                               configurations: ModelConfiguration(url: Store.url))
            let saved = (try? reopened?.mainContext.fetch(FetchDescriptor<Attachment>())) ?? []
            check("S-016 images survive reopening the store", saved.contains { $0.imageData?.isEmpty == false })

            transport.script(ScriptedTransport.reply(text: ["Still a gradient"]))
            model.send("Are you sure?")
            await model.waitForReply()
            check("S-016 later messages still carry the earlier image", transport.chatBodies.last?.contains("\"images\":[\"") == true)

            if let conversation = model.selectedConversation {
                let context = model.container.mainContext
                let before = (try? context.fetchCount(FetchDescriptor<Attachment>())) ?? -1
                model.delete(conversation)
                let after = (try? context.fetchCount(FetchDescriptor<Attachment>())) ?? -1
                check("S-014 deleting a conversation deletes its attachments", after == before - 1, "\(before) to \(after)")
            }
        }

        // S-017 PDFs
        do {
            model.newConversation()
            let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: folder) }
            let scan = folder.appending(path: "scan.pdf")
            try? SeedData.samplePDF(text: "").write(to: scan)
            await model.addFiles([scan])
            check("S-017 a PDF with no text is explained", model.attachmentNotice == "“scan.pdf” has no readable text.", model.attachmentNotice ?? "nil")
            check("S-017 and doesn't attach", model.draftAttachments.isEmpty)

            let report = folder.appending(path: "report.pdf")
            try? SeedData.samplePDF(text: "Revenue rose sharply").write(to: report)
            await model.addFiles([report])
            check("S-017 a PDF attaches with its page count", model.draftAttachments.first?.pageCount == 1)
            check("S-017 a successful attach clears the notice", model.attachmentNotice == nil)
            check("S-017 a short PDF has no warning", model.attachmentLengthWarning == nil)

            model.draftAttachments.append(LoadedAttachment(kind: .pdf, fileName: "huge.pdf", text: String(repeating: "a", count: 2_000), pageCount: 1))
            check("S-017 a long file is flagged before sending", model.attachmentLengthWarning?.contains("huge.pdf") == true && first.contextLimit == 100, model.attachmentLengthWarning ?? "nil")
            model.draftAttachments.removeLast()

            transport.script(ScriptedTransport.reply(text: ["It rose"]))
            model.send("What happened to revenue?")
            await model.waitForReply()
            let sent = transport.chatBodies.last ?? ""
            check("S-017 the PDF text reaches the model", sent.contains("Revenue rose sharply") && sent.contains("report.pdf"))
            check("S-017 your message stays clean in the conversation", model.selectedConversation?.ordered.first?.text == "What happened to revenue?")
        }

        // S-018 text files
        do {
            model.newConversation()
            let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: folder) }
            let binary = folder.appending(path: "app.zip")
            try? Data([0x50, 0x4B, 0x03, 0x04, 0x00]).write(to: binary)
            await model.addFiles([binary])
            check("S-018 a binary file is refused by name", model.attachmentNotice == "Unable to read “app.zip”. Attach an image, PDF, or text file.", model.attachmentNotice ?? "nil")
            let code = folder.appending(path: "main.swift")
            try? Data("let answer = 42".utf8).write(to: code)
            await model.addFiles([code])
            check("S-018 a text file attaches", model.draftAttachments.first?.kind == .text)
            transport.script(ScriptedTransport.reply(text: ["It's 42"]))
            model.send("What is answer?")
            await model.waitForReply()
            let sent = transport.chatBodies.last ?? ""
            check("S-018 the file reaches the model with its name", sent.contains("let answer = 42") && sent.contains("main.swift"))
        }

        // S-019 removing
        do {
            model.newConversation()
            await model.addPastedImage(SeedData.sampleImage)
            model.draftAttachments.append(LoadedAttachment(kind: .text, fileName: "keep.txt", text: "kept file text"))
            if let image = model.draftAttachments.first { model.removeAttachment(image.id) }
            check("S-019 only the removed attachment goes", model.draftAttachments.map(\.fileName) == ["keep.txt"])
            transport.script(ScriptedTransport.reply(text: ["Done"]))
            model.send("Check this")
            await model.waitForReply()
            let sent = transport.chatBodies.last ?? ""
            check("S-019 the removed file is not sent", !sent.contains("\"images\"") && sent.contains("kept file text"))
        }

        // S-020 models without vision
        do {
            let previous = model.selection
            defer { model.selection = previous }
            model.newConversation()
            model.draftModelName = "second:1"
            await model.addPastedImage(SeedData.sampleImage)
            check("S-020 an image is refused by name", model.attachmentNotice == "second:1 can't read images. Choose a model that can.", model.attachmentNotice ?? "nil")
            check("S-020 and doesn't attach", model.draftAttachments.isEmpty)
            model.draftAttachments.append(LoadedAttachment(kind: .text, fileName: "a.txt", text: "text works"))
            check("S-020 text files still work without vision", model.imageRefusal != nil && model.draftAttachments.count == 1)
            model.draftAttachments = []
            model.draftModelName = "first:1"
            await model.addPastedImage(SeedData.sampleImage)
            check("S-020 a vision model takes the image", model.draftAttachments.count == 1)
            model.draftModelName = "second:1"
            check("S-020 switching away blocks Send", !model.send("Look at this"))
            check("S-020 and keeps your attachment", model.draftAttachments.count == 1 && model.attachmentNotice?.contains("second:1") == true)
            model.draftAttachments = []
            model.attachmentNotice = nil
            model.draftModelName = nil
        }

        // S-021 Quick Ask panel
        do {
            let quick = QuickAskController.shared
            quick.show()
            try? await Task.sleep(for: .milliseconds(300))
            check("S-021 the panel opens", quick.isVisible)
            check("S-021 the panel takes keyboard focus", quick.window?.isKeyWindow == true)
            check("S-021 the field has focus at once", quick.window?.firstResponder is NSTextView)
            let main = NSApp.windows.first { $0.canBecomeMain && !$0.isSheet }
            check("S-021 the main window isn't the key window", main?.isKeyWindow == false)
            quick.toggle()
            check("S-021 the shortcut again hides it", !quick.isVisible)
            quick.show()
            try? await Task.sleep(for: .milliseconds(200))
            quick.window?.cancelOperation(nil)
            check("S-021 Escape hides it", !quick.isVisible)
            quick.hide()
            main?.makeKeyAndOrderFront(nil)
        }

        // S-022 replies in the panel
        do {
            let context = model.container.mainContext
            let before = (try? context.fetchCount(FetchDescriptor<Conversation>())) ?? -1
            let selectedBefore = model.selection
            model.quickAsk.conversation = nil
            model.quickAsk.draft = "  Quick question\nmore "
            transport.script(ScriptedTransport.reply(text: ["Quick answer"]))
            check("S-022 a quick ask sends", model.quickSend())
            await model.waitForReply()
            check("S-022 it's saved as a normal conversation", (try? context.fetchCount(FetchDescriptor<Conversation>())) == before + 1)
            check("S-022 it's titled like any other", model.quickAsk.conversation?.title == "Quick question")
            check("S-022 the reply is written", model.quickAsk.conversation?.ordered.last?.text == "Quick answer")
            check("S-022 the main window's selection doesn't move", model.selection == selectedBefore)
            check("S-022 the field clears", model.quickAsk.draft.isEmpty)
            model.quickAsk.draft = "A follow up"
            transport.script(ScriptedTransport.reply(text: ["More"]))
            model.quickSend()
            await model.waitForReply()
            check("S-022 a follow up stays in the same conversation", model.quickAsk.conversation?.messages.count == 4)
            check("S-022 a follow up carries the history", transport.chatBodies.last?.contains("Quick answer") == true)
            let conversation = model.quickAsk.conversation
            transport.script(ScriptedTransport.reply(text: ["Retried quickly"]))
            model.retry(conversation)
            await model.waitForReply()
            check("S-022 Retry works on the panel's conversation", conversation?.ordered.last?.text == "Retried quickly")
            QuickAskController.shared.show()
            check("S-022 reopening starts fresh", model.quickAsk.conversation == nil)
            QuickAskController.shared.hide()

            transport.script(ScriptedTransport.reply(text: Array(repeating: "x ", count: 100)), delay: .milliseconds(20))
            model.send("Busy now")
            try? await Task.sleep(for: .milliseconds(100))
            model.quickAsk.draft = "Too soon"
            check("S-022 a second reply waits its turn", !model.quickSend() && model.quickAsk.notice == "Lantern is finishing another reply.")
            check("S-022 and keeps your text", model.quickAsk.draft == "Too soon")
            model.stop()
            await model.waitForReply()
            model.quickAsk.draft = ""
            model.quickAsk.notice = nil
        }

        // S-023 opening in the window
        do {
            model.quickAsk.conversation = nil
            model.quickAsk.draft = "Carry this on"
            transport.script(ScriptedTransport.reply(text: ["Sure"]))
            model.quickSend()
            await model.waitForReply()
            let conversation = model.quickAsk.conversation
            QuickAskController.shared.show()
            model.quickAsk.conversation = conversation
            try? await Task.sleep(for: .milliseconds(200))
            model.openQuickAskInWindow()
            try? await Task.sleep(for: .milliseconds(300))
            check("S-023 the conversation is selected", model.selectedConversation?.uid == conversation?.uid)
            check("S-023 the panel closes", !QuickAskController.shared.isVisible)
            let main = NSApp.windows.first { $0.canBecomeMain && !($0 is NSPanel) }
            // Whether it becomes frontmost depends on the app you're using, so only check it's shown.
            check("S-023 the main window is shown", main?.isVisible == true)
        }

        // S-025 editing
        do {
            model.newConversation()
            transport.script(ScriptedTransport.reply(text: ["First reply"]))
            model.send("Old question")
            await model.waitForReply()
            let conversation = model.selectedConversation
            check("S-025 the menu allows editing", MenuState.shared.canEdit)
            model.startEditing()
            check("S-025 Edit targets your latest message", model.editingMessageID == model.latestUserMessage?.uid)
            model.cancelEditing()
            check("S-025 Escape cancels", model.editingMessageID == nil && conversation?.messages.count == 2)
            if let message = model.latestUserMessage {
                model.saveEdit(message, text: "   ")
                check("S-025 an empty edit changes nothing", message.text == "Old question" && conversation?.messages.count == 2)
                transport.script(ScriptedTransport.reply(text: ["Second reply"]))
                let oldReply = model.latestReply?.uid
                model.saveEdit(message, text: "New question")
                await model.waitForReply()
                check("S-025 the message changes", message.text == "New question")
                check("S-025 the old reply is gone", conversation?.messages.count == 2 && model.latestReply?.uid != oldReply)
                check("S-025 a new reply is written", model.latestReply?.text == "Second reply")
                let body = transport.chatBodies.last ?? ""
                check("S-025 the model sees only the new text", body.contains("New question") && !body.contains("Old question") && !body.contains("First reply"))
            }
        }

        // S-026 moving between conversations
        do {
            let previous = model.selection
            defer { model.selection = previous }
            let all = (try? model.container.mainContext.fetch(FetchDescriptor<Conversation>())) ?? []
            let groups = ConversationGroups.split(all, isPinned: \.isPinned, updatedAt: \.updatedAt)
            let order = (groups.pinned + groups.recent).map(\.uid)
            check("S-026 setup has conversations to move through", order.count >= 2)
            model.selection = nil
            model.selectAdjacentConversation(by: -1)
            check("S-026 up from a new conversation stays put", model.selection == nil)
            model.selectAdjacentConversation(by: 1)
            check("S-026 down from a new conversation selects the first", model.selection == order.first)
            model.selectAdjacentConversation(by: 1)
            check("S-026 next moves down", model.selection == order[1])
            model.selectAdjacentConversation(by: -1)
            check("S-026 previous moves up", model.selection == order[0])
            model.selectAdjacentConversation(by: -1)
            check("S-026 the top stays put", model.selection == order[0])
            model.selection = order.last
            model.selectAdjacentConversation(by: 1)
            check("S-026 the bottom stays put", model.selection == order.last)
        }

        // S-027 the Models page
        do {
            let previous = model.selection
            defer { model.selection = previous }
            transport.setLoaded(["first:1"])
            await model.refreshLoaded()
            check("S-027 the loaded model is known", model.loaded.map(\.name) == ["first:1"])
            model.showModels()
            check("S-027 the page opens", model.showingModels && model.selection == nil)
            model.newConversation()
            check("S-027 New Conversation leaves it", !model.showingModels)
            model.showModels()
            if let previous { model.selection = previous }
            check("S-027 picking a conversation leaves it", !model.showingModels)
            transport.setLoaded([])
            await model.refreshLoaded()
            check("S-027 an unloaded model drops off", model.loaded.isEmpty)
            model.newConversation()
            transport.setLoaded(["first:1"])
            transport.script(ScriptedTransport.reply(text: ["Ok"]))
            model.send("Refresh check")
            await model.waitForReply()
            check("S-027 finishing a reply refreshes the state", !model.loaded.isEmpty)
            transport.setLoaded([])
        }

        // S-028 unloading
        do {
            transport.setLoaded(["first:1"])
            await model.refreshLoaded()
            await model.unload("first:1")
            check("S-028 Unload frees the model", model.loaded.isEmpty)
            check("S-028 Unload asks Ollama for keep_alive 0", transport.requests.last { $0.path.hasSuffix("/api/generate") }?.body.contains("\"keep_alive\":0") == true)

            model.newConversation()
            model.draftModelName = "first:1"
            transport.script(ScriptedTransport.reply(text: Array(repeating: "x ", count: 100)), delay: .milliseconds(20))
            model.send("Keep writing")
            try? await Task.sleep(for: .milliseconds(150))
            check("S-028 the writing model can't be unloaded", !model.canUnload("first:1"))
            check("S-028 another model still can", model.canUnload("second:1"))
            transport.setLoaded(["first:1"])
            await model.refreshLoaded()
            await model.unload("first:1")
            check("S-028 and asking anyway changes nothing", model.loaded.map(\.name) == ["first:1"])
            model.stop()
            await model.waitForReply()
            check("S-028 it can be unloaded once the reply ends", model.canUnload("first:1"))
            model.draftModelName = nil
            transport.setLoaded([])
            await model.refreshLoaded()
        }

        // S-029 how long models stay loaded
        do {
            check("S-029 the default is 5 minutes", model.keepLoadedMinutes == 5)
            model.keepLoadedMinutes = 15
            model.newConversation()
            transport.script(ScriptedTransport.reply(text: ["Ok"]))
            model.send("Timer check")
            await model.waitForReply()
            check("S-029 the setting reaches the request", transport.chatBodies.last?.contains("\"keep_alive\":\"15m\"") == true)
            model.keepLoadedMinutes = 5
        }

        // S-031 the default model
        do {
            let previous = model.selection
            defer { model.selection = previous }
            model.chosenDefaultModel = "second:1"
            model.newConversation()
            check("S-031 a new conversation uses the default", model.currentModelName == "second:1")
            check("S-031 Quick Ask uses the default", model.defaultModelName == "second:1")
            model.chooseModel("first:1")
            check("S-031 you can still pick another for one conversation", model.currentModelName == "first:1")
            model.newConversation()
            check("S-031 the next new conversation goes back to the default", model.currentModelName == "second:1")
            model.chosenDefaultModel = ""
        }

        // S-032 changing the shortcut
        do {
            let free = Hotkey(keyCode: kVK_ANSI_K, modifiers: controlKey | optionKey | shiftKey)
            let other = Hotkey(keyCode: kVK_ANSI_J, modifiers: controlKey | optionKey | shiftKey)
            model.changeHotkey(Hotkey(keyCode: kVK_ANSI_K, modifiers: shiftKey))
            check("S-032 a shortcut with no modifier is refused", model.hotkeyMessage == "Include ⌘, ⌃, or ⌥ in the shortcut." && model.hotkey == .standard)
            check("S-032 an unused shortcut isn't reported as taken", !GlobalHotKey.isReservedBySystem(free))
            model.changeHotkey(free)
            check("S-032 a new shortcut is accepted", model.hotkey == free && model.hotkeyMessage == nil)
            check("S-032 the menu shows the new shortcut", MenuState.shared.quickAskHotkey == free)
            let rival = GlobalHotKey()
            check("S-032 the new shortcut is really held", !rival.register(free))
            model.changeHotkey(other)
            check("S-032 the old shortcut stops being held", rival.register(free))
            rival.unregister()
            print("INFO Command-Space reserved by macOS: \(GlobalHotKey.isReservedBySystem(Hotkey(keyCode: kVK_Space, modifiers: cmdKey)))")
            GlobalHotKey.shared.unregister()
            model.hotkey = .standard
            model.hotkeyMessage = nil
        }

        // S-034 models appearing while Lantern was away
        do {
            let installed = model.models
            model.models = []
            await model.refreshInstalledModels()
            check("S-034 coming back picks up installed models", model.models.map(\.name) == installed.map(\.name))
        }

        // S-037 naming a model
        do {
            let previous = model.selection
            defer { model.selection = previous }
            check("S-037 without a name, the original shows", model.displayName("first:1") == "first:1")
            model.setNickname("  Fast One ", for: "first:1")
            check("S-037 a name is saved, trimmed", model.displayName("first:1") == "Fast One")
            model.setNickname("first:1", for: "first:1")
            check("S-037 the original as a name is no name", model.modelNicknames["first:1"] == nil)
            model.setNickname("Words Only", for: "second:1")
            model.newConversation()
            model.draftModelName = "second:1"
            await model.addPastedImage(SeedData.sampleImage)
            check("S-037 messages use your name", model.attachmentNotice == "Words Only can't read images. Choose a model that can.", model.attachmentNotice ?? "nil")
            model.attachmentNotice = nil
            model.draftModelName = nil
            model.setNickname("", for: "second:1")
            check("S-037 an empty name restores the original", model.displayName("second:1") == "second:1")
        }

        // S-038 changing the model in Quick Ask
        do {
            model.quickAsk.conversation = nil
            model.chooseQuickModel("second:1")
            check("S-038 the choice shows at once", model.quickModelName == "second:1")
            model.quickAsk.draft = "Which model?"
            transport.script(ScriptedTransport.reply(text: ["This one"]))
            model.quickSend()
            await model.waitForReply()
            check("S-038 the message uses the chosen model", model.quickAsk.conversation?.ordered.last?.modelName == "second:1")
            model.chooseQuickModel("first:1")
            model.quickAsk.draft = "And now?"
            transport.script(ScriptedTransport.reply(text: ["That one"]))
            model.quickSend()
            await model.waitForReply()
            check("S-038 a conversation can switch models", model.quickAsk.conversation?.ordered.last?.modelName == "first:1")
            QuickAskController.shared.show()
            check("S-038 reopening goes back to the default", model.quickAsk.modelName == nil)
            QuickAskController.shared.hide()
        }

        // S-039 memory warnings
        do {
            let previous = model.selection
            defer {
                model.selection = previous
                model.readMemory = { MemorySnapshot(totalBytes: 68_719_476_736, availableBytes: 34_359_738_368) }
                model.readTopApps = { [] }
            }
            let gigabyte: Int64 = 1_073_741_824
            model.models.append(OllamaModel(name: "big:1", size: 8 * gigabyte))
            defer { model.models.removeAll { $0.name == "big:1" } }
            model.readMemory = { MemorySnapshot(totalBytes: 16 * gigabyte, availableBytes: 4 * gigabyte) }
            model.readTopApps = { [SystemMonitor.AppMemory(name: "Big Editor", bytes: 6 * gigabyte)] }
            model.newConversation()
            model.draftModelName = "big:1"
            let conversations = (try? model.container.mainContext.fetchCount(FetchDescriptor<Conversation>())) ?? -1
            check("S-039 sending is held", !model.send("Heavy question"))
            check("S-039 nothing is created yet", (try? model.container.mainContext.fetchCount(FetchDescriptor<Conversation>())) == conversations)
            check("S-039 the warning names the app using memory", model.memoryWarning?.appsSummary.contains("Big Editor") == true, model.memoryWarning?.appsSummary ?? "nil")
            check("S-039 the warning names the model", model.memoryWarning?.message.contains("big:1") == true)
            model.readMemory = { MemorySnapshot(totalBytes: 16 * gigabyte, availableBytes: 14 * gigabyte) }
            model.recheckMemory()
            check("S-039 Check Again clears it once there's room", model.memoryWarning == nil)
            model.readMemory = { MemorySnapshot(totalBytes: 16 * gigabyte, availableBytes: 4 * gigabyte) }
            transport.setLoaded(["big:1"])
            await model.refreshLoaded()
            check("S-039 a loaded model is never warned about", model.memoryWarningIfNeeded(for: "big:1", surface: .main) == nil)
            transport.setLoaded([])
            await model.refreshLoaded()
            transport.script(ScriptedTransport.reply(text: ["Done"]))
            check("S-039 Send Anyway goes ahead", model.send("Heavy question", skipMemoryCheck: true))
            await model.waitForReply()
            check("S-039 sending clears the warning", model.memoryWarning == nil)
            model.draftModelName = nil
        }

        // S-040 the Model Lab
        do {
            let previous = model.selection
            defer { model.selection = previous }
            transport.scriptLab { body in
                if body.contains("17 sheep") { return "9" }
                if body.contains("is_even") { return "def is_even(n):\\n    return n % 2 == 0" }
                return "No idea"
            }
            model.openLab("first:1")
            check("S-040 the page opens", model.labModelName == "first:1")
            model.runLab("first:1")
            check("S-040 a run starts", model.lab.modelName == "first:1")
            check("S-040 nothing else can use the model meanwhile", model.isWriting && !model.canUnload("first:1"))
            await model.lab.wait()
            let report = model.labReports["first:1"]
            check("S-040 a report is produced", report != nil)
            check("S-040 grading tells right from wrong", report?.passed(in: .reasoning) == 1, "\(report?.passed(in: .reasoning) ?? -1)")
            check("S-040 speed and load time are measured", report?.tokensPerSecond == 20 && report?.loadSeconds == 3)
            check("S-040 the tool test runs for tool models only", report?.results(in: .tools).isEmpty == true)
            check("S-040 the model is freed afterwards", transport.requests.last?.path.hasSuffix("/api/generate") == true || transport.requests.last?.path.hasSuffix("/api/ps") == true)
            check("S-040 it can be used again", !model.isWriting)

            model.labReports["first:1"] = nil
            model.loadLabReport("first:1")
            check("S-040 the report is saved", model.labReports["first:1"]?.results.count == report?.results.count)

            let runs = (try? model.container.mainContext.fetchCount(FetchDescriptor<ModelTestRun>())) ?? -1
            model.runLab("first:1")
            model.lab.stop()
            await model.lab.wait()
            check("S-040 Stop ends a run without saving it", (try? model.container.mainContext.fetchCount(FetchDescriptor<ModelTestRun>())) == runs && !model.lab.isRunning)
            model.closeLab()
            check("S-040 Models takes you back", model.showingModels && model.labModelName == nil)
            model.newConversation()
        }

        // Launch repair
        let stale = Message(role: .assistant, text: "Cut", modelName: "first:1", sequence: 99, state: .writing)
        model.selectedConversation?.messages.append(stale)
        model.repairInterruptedReplies()
        check("a reply left writing at launch becomes interrupted", stale.state == .interrupted)

        // Leaves whatever you had copied in place.
        let clipboard = NSPasteboard.general.string(forType: .string)
        Clipboard.copy("copy check")
        check("S-009 Copy reaches the clipboard", NSPasteboard.general.string(forType: .string) == "copy check")
        if let clipboard { Clipboard.copy(clipboard) }
    }

    /// One real round trip through Ollama. Unloads the model afterwards.
    private static func runLive(_ model: AppModel, modelName: String) async {
        model.client = OllamaClient()
        await model.connect()
        check("LIVE connects to Ollama", model.connection == .connected)
        check("LIVE the model is installed", model.models.contains { $0.name == modelName })
        model.newConversation()
        model.draftModelName = modelName
        check("LIVE sends a message", model.send("Reply with exactly: ok", skipMemoryCheck: true))
        await model.waitForReply()
        let reply = model.latestReply
        check("LIVE the reply finishes", reply?.state == .complete, reply?.failureText ?? "")
        check("LIVE the reply has text", !(reply?.text.isEmpty ?? true), reply?.text ?? "nil")
        check("LIVE thinking arrives apart from the reply", !(reply?.thinking.isEmpty ?? true))
        print("LIVE reply: \(reply?.text ?? "") at \(Int(reply?.tokensPerSecond ?? 0)) tokens per second")
        model.quickAsk.conversation = nil
        model.quickAsk.draft = "Reply with exactly: quick ok"
        check("LIVE Quick Ask sends", model.quickSend(skipMemoryCheck: true))
        await model.waitForReply()
        let quickReply = model.quickAsk.conversation?.ordered.last
        check("LIVE Quick Ask gets a reply", quickReply?.state == .complete && !(quickReply?.text.isEmpty ?? true), quickReply?.failureText ?? "")
        print("LIVE Quick Ask reply: \(quickReply?.text ?? "")")
        try? await model.client.unload(modelName)
    }

    private static func check(_ name: String, _ ok: Bool, _ detail: String = "") {
        count += 1
        if !ok { failures += 1 }
        print(ok ? "PASS \(name)" : "FAIL \(name)\(detail.isEmpty ? "" : ": \(detail)")")
    }

    /// Quits through NSApp.terminate, never exit(), and closes sheets first:
    /// an open sheet refuses terminate, and the run would wait forever.
    static func finish(code: Int32) {
        exitCode = code
        for window in NSApp.windows { if let sheet = window.attachedSheet { window.endSheet(sheet) } }
        NSApp.terminate(nil)
    }
}
