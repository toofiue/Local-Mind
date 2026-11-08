import AppKit
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
        let first = OllamaModel(name: "first:1", size: 100, capabilities: ["completion", "thinking"])
        let second = OllamaModel(name: "second:1", size: 200, capabilities: ["completion"])
        let transport = ScriptedTransport(installed: [first, second])
        model.client = OllamaClient(transport: transport)
        model.startOllama = {}
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
        let reopened = try? ModelContainer(for: Conversation.self, Message.self,
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
        check("LIVE sends a message", model.send("Reply with exactly: ok"))
        await model.waitForReply()
        let reply = model.latestReply
        check("LIVE the reply finishes", reply?.state == .complete, reply?.failureText ?? "")
        check("LIVE the reply has text", !(reply?.text.isEmpty ?? true), reply?.text ?? "nil")
        check("LIVE thinking arrives apart from the reply", !(reply?.thinking.isEmpty ?? true))
        print("LIVE reply: \(reply?.text ?? "") at \(Int(reply?.tokensPerSecond ?? 0)) tokens per second")
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
