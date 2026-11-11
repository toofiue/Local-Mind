import Foundation
import Testing
@testable import LanternKit

/// Speaks a phrase into a file, in a format Ollama can't read directly.
private func spokenFile(_ text: String, format: String) throws -> URL {
    let url = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString + "." + format)
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/say")
    process.arguments = ["-o", url.path, text]
    try process.run()
    process.waitUntilExit()
    return url
}

@Test("S-045 audio becomes 16 kHz mono WAV", arguments: ["aiff", "m4a"])
func convertsAudio(format: String) throws {
    let source = try spokenFile("The code word is marigold.", format: format)
    defer { try? FileManager.default.removeItem(at: source) }
    let attachment = try AttachmentLoader.load(contentsOf: source)
    #expect(attachment.kind == .audio)
    let wav = try #require(attachment.audioData)
    #expect(wav.starts(with: Data("RIFF".utf8)))
    #expect(wav[8..<12] == Data("WAVE".utf8))
    let sampleRate = wav[24..<28].enumerated().reduce(0) { $0 | Int($1.element) << (8 * $1.offset) }
    let channels = Int(wav[22]) | Int(wav[23]) << 8
    #expect(sampleRate == 16_000)
    #expect(channels == 1)
    #expect(attachment.durationSeconds > 0.5 && attachment.durationSeconds < 10)
}

@Test("S-045 a file that only looks like audio is refused")
func refusesFakeAudio() throws {
    let url = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString + ".mp3")
    try Data("not audio".utf8).write(to: url)
    defer { try? FileManager.default.removeItem(at: url) }
    #expect(throws: AttachmentError.unsupported(url.lastPathComponent)) { try AttachmentLoader.load(contentsOf: url) }
}

@Test("S-045 only models that list audio can take it")
func readsAudioCapability() {
    #expect(OllamaModel(name: "a", size: 1, capabilities: ["audio"]).supportsAudio)
    #expect(!OllamaModel(name: "b", size: 1, capabilities: ["vision"]).supportsAudio)
}

@Test("S-050 a long recording isn't refused")
func acceptsLongAudio() throws {
    let url = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString + ".aiff")
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/say")
    process.arguments = ["-r", "500", "-o", url.path, String(repeating: "This sentence keeps going for a long while. ", count: 420)]
    try process.run()
    process.waitUntilExit()
    defer { try? FileManager.default.removeItem(at: url) }
    let attachment = try AttachmentLoader.load(contentsOf: url)
    #expect(attachment.durationSeconds > 300)
}
