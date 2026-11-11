import AppKit
import Foundation
import UniformTypeIdentifiers
import LanternKit

extension AppModel {
    /// Asks which files to attach, then attaches them.
    func chooseFiles() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.begin { [weak self] response in
            guard response == .OK else { return }
            let urls = panel.urls
            Task { @MainActor in await self?.addFiles(urls) }
        }
    }

    func addFiles(_ urls: [URL]) async {
        attachmentNotice = nil
        for url in urls where url.isFileURL {
            do {
                let loaded = try await Task.detached { try AttachmentLoader.load(contentsOf: url) }.value
                addIfSupported(loaded)
            } catch {
                show(error, fileName: url.lastPathComponent)
            }
        }
        focusRequest += 1
    }

    func addPastedImage(_ data: Data) async {
        attachmentNotice = nil
        do {
            let loaded = try await Task.detached { try AttachmentLoader.load(name: "Pasted Image", data: data) }.value
            addIfSupported(loaded)
        } catch {
            show(error, fileName: "Pasted Image")
        }
    }

    private func addIfSupported(_ loaded: LoadedAttachment) {
        if loaded.kind == .image, let refusal = imageRefusal {
            attachmentNotice = refusal
        } else if loaded.kind == .audio, let refusal = audioRefusal {
            attachmentNotice = refusal
        } else {
            draftAttachments.append(loaded)
        }
    }

    /// Why the current model can't take images, or nil if it can.
    var imageRefusal: String? {
        guard let model = models.first(where: { $0.name == currentModelName }), !model.supportsImages else { return nil }
        return "\(displayName(model.name)) can't read images. Choose a model that can."
    }

    /// Why the current model can't take audio, or nil if it can.
    var audioRefusal: String? {
        guard let model = models.first(where: { $0.name == currentModelName }), !model.supportsAudio else { return nil }
        return "\(displayName(model.name)) can't listen to audio. Choose a model that can."
    }

    func removeAttachment(_ id: UUID) {
        draftAttachments.removeAll { $0.id == id }
        attachmentNotice = nil
    }

    private func show(_ error: Error, fileName: String) {
        if case AttachmentError.noReadableText = error {
            attachmentNotice = "“\(fileName)” has no readable text."
        } else {
            attachmentNotice = "Unable to read “\(fileName)”. Attach an image, PDF, or text file."
        }
    }

    /// The history turn for one stored message, with its attachments.
    func turn(for message: Message) -> ChatTurn {
        let attachments = message.orderedAttachments
        // Ollama takes images and audio in the same list.
        let images = attachments.compactMap { ($0.imageData ?? $0.audioData)?.base64EncodedString() }
        let files = attachments.filter { $0.kind == .pdf || $0.kind == .text }.map { (name: $0.fileName, text: $0.text) }
        let media = attachments.filter { $0.kind == .image || $0.kind == .audio }.map { (kind: $0.kind, name: $0.fileName) }
        return ChatTurn(role: message.role.rawValue,
                        content: AttachmentPrompt.compose(message: message.text, files: files, media: media),
                        images: images.isEmpty ? nil : images)
    }

    /// A warning if an attached file is too long for the current model. Sending is still allowed.
    var attachmentLengthWarning: String? {
        guard let limit = models.first(where: { $0.name == currentModelName })?.contextLimit else { return nil }
        let tooLong = draftAttachments.first { ($0.kind == .pdf || $0.kind == .text) && AttachmentPrompt.exceedsContext($0.text, limit: limit) }
        return tooLong.map { "“\($0.fileName)” is longer than this model can read at once. It may only see part of it." }
    }
}
