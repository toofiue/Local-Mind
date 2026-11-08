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
                draftAttachments.append(loaded)
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
            draftAttachments.append(loaded)
        } catch {
            show(error, fileName: "Pasted Image")
        }
    }

    private func show(_ error: Error, fileName: String) {
        attachmentNotice = "Unable to read “\(fileName)”. Attach an image, PDF, or text file."
    }

    /// The history turn for one stored message, with its attachments.
    func turn(for message: Message) -> ChatTurn {
        let images = message.orderedAttachments.compactMap { $0.imageData?.base64EncodedString() }
        return ChatTurn(role: message.role.rawValue, content: message.text, images: images.isEmpty ? nil : images)
    }
}
