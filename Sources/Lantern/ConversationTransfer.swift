import AppKit
import LanternKit
import SwiftData
import UniformTypeIdentifiers

/// Getting conversations out of Local Mind and back in: Markdown, PDF, the share sheet,
/// and a backup file of a whole profile.
extension AppModel {
    func exported(_ conversation: Conversation) -> ExportedConversation {
        ExportedConversation(
            uid: conversation.uid, title: conversation.title, modelName: conversation.modelName,
            createdAt: conversation.createdAt, updatedAt: conversation.updatedAt, isPinned: conversation.isPinned,
            messages: conversation.ordered.map { message in
                ExportedMessage(uid: message.uid, role: message.roleValue, text: message.text, thinking: message.thinking,
                                modelName: message.modelName, createdAt: message.createdAt, sequence: message.sequence,
                                state: message.stateValue,
                                attachments: message.orderedAttachments.map { file in
                                    ExportedAttachment(kind: file.kindValue, fileName: file.fileName, text: file.text,
                                                       pageCount: file.pageCount, durationSeconds: file.durationSeconds,
                                                       sequence: file.sequence, imageData: file.imageData,
                                                       audioData: file.audioData, fileData: file.fileData)
                                })
            })
    }

    func markdown(for conversation: Conversation) -> String {
        ChatExport.markdown(exported(conversation), displayName: displayName)
    }

    func copyMarkdown(of conversation: Conversation) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(markdown(for: conversation), forType: .string)
    }

    func saveMarkdown(of conversation: Conversation) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "md") ?? .plainText]
        panel.nameFieldStringValue = Self.fileName(for: conversation.title) + ".md"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        try? markdown(for: conversation).write(to: url, atomically: true, encoding: .utf8)
    }

    func savePDF(of conversation: Conversation) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        panel.nameFieldStringValue = Self.fileName(for: conversation.title) + ".pdf"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        writePDF(of: conversation, to: url)
    }

    /// The Mac's share sheet (AirDrop, Messages, Mail, Notes) with the conversation as a PDF.
    func share(_ conversation: Conversation) {
        let folder = FileManager.default.temporaryDirectory.appending(path: "Local Mind Share", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appending(path: Self.fileName(for: conversation.title) + ".pdf")
        writePDF(of: conversation, to: url)
        guard let window = NSApp.keyWindow ?? NSApp.mainWindow, let view = window.contentView else { return }
        let picker = NSSharingServicePicker(items: [url])
        // Under the toolbar's top-right corner, where the Share button is.
        picker.show(relativeTo: NSRect(x: view.bounds.maxX - 140, y: view.bounds.maxY - 52, width: 1, height: 1), of: view, preferredEdge: .minY)
    }

    /// A clean, paginated PDF: the title, then each turn under who said it.
    func writePDF(of conversation: Conversation, to url: URL) {
        let body = NSFont.systemFont(ofSize: 12)
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 3
        paragraph.paragraphSpacing = 8
        let text = NSMutableAttributedString(string: conversation.title + "\n\n",
                                             attributes: [.font: NSFont(descriptor: NSFontDescriptor.preferredFontDescriptor(forTextStyle: .title1).withDesign(.serif) ?? body.fontDescriptor, size: 22) ?? body])
        for message in conversation.ordered where !message.text.isEmpty || !message.attachments.isEmpty {
            let who = message.role == .user ? "You" : displayName(message.modelName)
            text.append(NSAttributedString(string: who + "\n", attributes: [.font: NSFont.systemFont(ofSize: 11, weight: .medium),
                                                                             .foregroundColor: NSColor.secondaryLabelColor]))
            for file in message.orderedAttachments {
                text.append(NSAttributedString(string: "Attached: \(file.fileName)\n", attributes: [.font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor.secondaryLabelColor]))
            }
            let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
            let styled = (try? AttributedString(markdown: message.text, options: options)) ?? AttributedString(message.text)
            let line = NSMutableAttributedString(styled)
            line.addAttributes([.font: body, .paragraphStyle: paragraph, .foregroundColor: NSColor.black],
                               range: NSRange(location: 0, length: line.length))
            text.append(line)
            text.append(NSAttributedString(string: "\n\n"))
        }
        let info = NSPrintInfo()
        info.paperSize = NSSize(width: 595, height: 842) // grid: ok A4 page in points
        info.topMargin = 56; info.bottomMargin = 56; info.leftMargin = 56; info.rightMargin = 56
        info.jobDisposition = .save
        info.dictionary()[NSPrintInfo.AttributeKey.jobSavingURL] = url
        let view = NSTextView(frame: NSRect(x: 0, y: 0, width: 595 - 112, height: 10)) // grid: ok A4 page in points
        view.textStorage?.setAttributedString(text)
        view.backgroundColor = .white
        view.sizeToFit()
        let operation = NSPrintOperation(view: view, printInfo: info)
        operation.showsPrintPanel = false
        operation.showsProgressPanel = false
        operation.run()
    }

    // MARK: Backup

    func backupConversations() {
        let all = (try? context.fetch(FetchDescriptor<Conversation>(sortBy: [SortDescriptor(\.updatedAt)]))) ?? []
        let backup = ConversationBackup(profileName: ProfileStore.shared.current.name, conversations: all.map(exported))
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "Local Mind – \(ProfileStore.shared.current.name) – \(Date.now.formatted(.iso8601.year().month().day())).json"
        guard panel.runModal() == .OK, let url = panel.url, let data = try? backup.encoded() else { return }
        try? data.write(to: url, options: .atomic)
    }

    /// Adds the conversations from a backup file. Ones already here are skipped, so importing twice is safe.
    @discardableResult
    func importConversations(from url: URL? = nil) -> Int? {
        var file = url
        if file == nil {
            let panel = NSOpenPanel()
            panel.allowedContentTypes = [.json]
            panel.message = "Choose a Local Mind backup"
            guard panel.runModal() == .OK else { return nil }
            file = panel.url
        }
        guard let file, let data = try? Data(contentsOf: file), let backup = try? ConversationBackup.decode(data) else { return nil }
        let existing = Set(((try? context.fetch(FetchDescriptor<Conversation>())) ?? []).map(\.uid))
        var added = 0
        for item in backup.conversations where !existing.contains(item.uid) {
            let conversation = Conversation(modelName: item.modelName)
            conversation.uid = item.uid
            conversation.title = item.title
            conversation.createdAt = item.createdAt
            conversation.updatedAt = item.updatedAt
            conversation.isPinned = item.isPinned
            context.insert(conversation)
            for saved in item.messages {
                let message = Message(role: MessageRole(rawValue: saved.role) ?? .user, text: saved.text,
                                      modelName: saved.modelName, sequence: saved.sequence)
                message.uid = saved.uid
                message.thinking = saved.thinking
                message.createdAt = saved.createdAt
                // A reply cut off mid-way stays marked as interrupted, never as still writing.
                message.stateValue = saved.state == ReplyState.writing.rawValue ? ReplyState.interrupted.rawValue : saved.state
                conversation.messages.append(message)
                for part in saved.attachments {
                    let loaded = LoadedAttachment(kind: AttachmentKind(rawValue: part.kind) ?? .text, fileName: part.fileName,
                                                  imageData: part.imageData, text: part.text, pageCount: part.pageCount,
                                                  audioData: part.audioData, durationSeconds: part.durationSeconds)
                    var withFile = loaded
                    withFile.fileData = part.fileData
                    message.attachments.append(Attachment(withFile, sequence: part.sequence))
                }
            }
            added += 1
        }
        save()
        return added
    }

    private static func fileName(for title: String) -> String {
        let cleaned = title.components(separatedBy: CharacterSet(charactersIn: "/:\\?%*|\"<>")).joined(separator: " ")
        return String(cleaned.prefix(80)).trimmingCharacters(in: .whitespaces)
    }
}
