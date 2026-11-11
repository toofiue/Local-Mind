import Foundation
import LanternKit

/// Reads each Lab clip aloud with macOS's voices, then converts it the way attachments are.
enum LabAudioRenderer {
    nonisolated static func render() -> [String: String] {
        var result: [String: String] = [:]
        let folder = FileManager.default.temporaryDirectory.appending(path: "Local Mind Lab Audio", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        for clip in LabAudio.clips {
            let spoken = folder.appending(path: clip.id + ".aiff")
            let say = Process()
            say.executableURL = URL(fileURLWithPath: "/usr/bin/say")
            say.arguments = (clip.voice.map { ["-v", $0] } ?? []) + (clip.rate.map { ["-r", String($0)] } ?? [])
                + ["-o", spoken.path, clip.script]
            say.standardError = FileHandle.nullDevice
            guard (try? say.run()) != nil else { continue }
            say.waitUntilExit()
            if let wav = try? AttachmentLoader.load(contentsOf: spoken).audioData {
                result[clip.id] = wav.base64EncodedString()
            }
        }
        return result
    }
}
