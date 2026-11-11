import Foundation
import LanternKit

/// Writes an attachment to a temporary file, so Quick Look can show it.
enum AttachmentPreview {
    private static var folder: URL {
        FileManager.default.temporaryDirectory.appending(path: "Local Mind Previews", directoryHint: .isDirectory)
    }

    static func file(kind: AttachmentKind, fileName: String, imageData: Data?, audioData: Data?, fileData: Data?, text: String) -> URL? {
        let data: Data?
        var name = fileName
        switch kind {
        case .image:
            data = imageData
        case .audio:
            // The stored audio was converted to WAV, so the name must say so for Quick Look to play it.
            data = audioData
            name = (fileName as NSString).deletingPathExtension + ".wav"
        case .pdf, .text:
            if let fileData {
                data = fileData
            } else {
                // Saved before originals were kept: show the text that was read from it.
                data = Data(text.utf8)
                name = (fileName as NSString).deletingPathExtension + ".txt"
            }
        }
        guard let data else { return nil }
        // A fresh folder each time, so an old preview is never shown by mistake.
        try? FileManager.default.removeItem(at: folder)
        let target = folder.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        let url = target.appending(path: name)
        return (try? data.write(to: url)) != nil ? url : nil
    }
}
