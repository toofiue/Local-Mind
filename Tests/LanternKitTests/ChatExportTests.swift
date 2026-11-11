import Foundation
import Testing
@testable import LanternKit

private func sample() -> ExportedConversation {
    let date = Date(timeIntervalSince1970: 1_800_000_000)
    return ExportedConversation(uid: UUID(), title: "Swift actors", modelName: "gemma4:12b", createdAt: date, updatedAt: date, isPinned: true, messages: [
        ExportedMessage(uid: UUID(), role: "assistant", text: "An **actor** protects its state.", thinking: "", modelName: "gemma4:12b",
                        createdAt: date, sequence: 1, state: "complete", attachments: []),
        ExportedMessage(uid: UUID(), role: "user", text: "Explain actors", thinking: "", modelName: "gemma4:12b", createdAt: date, sequence: 0,
                        state: "complete", attachments: [ExportedAttachment(kind: "pdf", fileName: "notes.pdf", text: "x", pageCount: 1,
                                                                            durationSeconds: 0, sequence: 0, imageData: nil, audioData: nil, fileData: Data([1, 2]))]),
    ])
}

@Test("S-070 a chat exports as Markdown, in order, under who said it")
func exportsMarkdown() {
    let markdown = ChatExport.markdown(sample(), displayName: { $0 == "gemma4:12b" ? "Gemma" : $0 })
    #expect(markdown.hasPrefix("# Swift actors"))
    let you = markdown.range(of: "**You**")!, gemma = markdown.range(of: "**Gemma**")!
    #expect(you.lowerBound < gemma.lowerBound)
    #expect(markdown.contains("*Attached: notes.pdf*"))
}

@Test("S-071 a backup round-trips exactly, attachments included")
func backupRoundTrips() throws {
    let backup = ConversationBackup(profileName: "Toufique", conversations: [sample()])
    let restored = try ConversationBackup.decode(backup.encoded())
    #expect(restored.conversations == backup.conversations)
    #expect(restored.conversations[0].messages[1].attachments[0].fileData == Data([1, 2]))
}

@Test("S-073 read-aloud text has no Markdown symbols or code")
func speaksPlainText() {
    let text = ChatExport.speakable("""
    ## Actors
    An **actor** protects its `state`.
    - First point
    ```swift
    actor Counter {}
    ```
    | Type | Safe |
    |---|---|
    | Actor | Yes |
    See [the docs](https://swift.org).
    """)
    #expect(text == "Actors An actor protects its state. First point There's a code example here. Type, Safe. Actor, Yes. See the docs.")
}
