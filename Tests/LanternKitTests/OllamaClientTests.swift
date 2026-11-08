import Foundation
import Testing
@testable import LanternKit

private let gemma = OllamaModel(name: "gemma4:12b-mlx", size: 7_700, capabilities: ["completion", "thinking", "vision"])
private let plain = OllamaModel(name: "plain:1", size: 1_000, capabilities: ["completion"])

private func collect(_ stream: AsyncThrowingStream<ChatEvent, Error>) async throws -> [ChatEvent] {
    var events: [ChatEvent] = []
    for try await event in stream { events.append(event) }
    return events
}

@Test("S-001 lists every model with its size and capabilities")
func listsModels() async throws {
    let client = OllamaClient(transport: ScriptedTransport(installed: [gemma, plain]))
    let models = try await client.models()
    #expect(models.map(\.name) == ["gemma4:12b-mlx", "plain:1"])
    #expect(models[0].size == 7_700)
    #expect(models[0].supportsThinking)
    #expect(!models[1].supportsThinking)
}

@Test("S-003 decodes real chunks from Ollama")
func decodesRealChunks() throws {
    let thinking = #"{"model":"m","created_at":"t","message":{"role":"assistant","content":"","thinking":"The"},"done":false}"#
    let content = #"{"model":"m","created_at":"t","message":{"role":"assistant","content":"ok"},"done":false}"#
    let final = #"{"model":"m","message":{"role":"assistant","content":""},"done":true,"done_reason":"stop","eval_count":38,"eval_duration":2000000000}"#
    #expect(try ChatStreamDecoder.decode(thinking) == [.thinking("The")])
    #expect(try ChatStreamDecoder.decode(content) == [.text("ok")])
    #expect(try ChatStreamDecoder.decode(final) == [.done(tokensPerSecond: 19)])
}

@Test("An error line from Ollama becomes a server error")
func decodesErrors() {
    #expect(throws: OllamaError.server("model 'nope:1' not found")) {
        try ChatStreamDecoder.decode(#"{"error":"model 'nope:1' not found"}"#)
    }
}

@Test("S-003 a request carries the whole conversation in order")
func sendsHistory() async throws {
    let transport = ScriptedTransport(installed: [gemma])
    transport.script(ScriptedTransport.reply(text: ["ok"]))
    let turns = [ChatTurn(role: "user", content: "one"), ChatTurn(role: "assistant", content: "two"), ChatTurn(role: "user", content: "three")]
    _ = try await collect(OllamaClient(transport: transport).chat(model: gemma.name, turns: turns, think: false))
    struct Sent: Decodable { struct Row: Decodable { let content: String }; let messages: [Row] }
    let sent = try JSONDecoder().decode(Sent.self, from: Data(transport.chatBodies[0].utf8))
    #expect(sent.messages.map(\.content) == ["one", "two", "three"])
}

@Test("S-003 replies with no text are left out of the history")
func dropsEmptyTurns() {
    let turns = [ChatTurn(role: "user", content: "hi"), ChatTurn(role: "assistant", content: "")]
    #expect(ChatHistory.turns(turns) == [ChatTurn(role: "user", content: "hi")])
}

@Test("S-010 thinking and reply chunks arrive as separate events")
func separatesThinking() async throws {
    let transport = ScriptedTransport(installed: [gemma])
    transport.script(ScriptedTransport.reply(thinking: ["hm"], text: ["yes"]))
    let events = try await collect(OllamaClient(transport: transport).chat(model: gemma.name, turns: [], think: true))
    #expect(events.prefix(2) == [.thinking("hm"), .text("yes")])
}

@Test("S-010 the think option is sent only when asked for", arguments: [true, false])
func sendsThinkOption(think: Bool) async throws {
    let transport = ScriptedTransport(installed: [gemma])
    transport.script(ScriptedTransport.reply(text: ["ok"]))
    _ = try await collect(OllamaClient(transport: transport).chat(model: gemma.name, turns: [], think: think))
    #expect(transport.chatBodies[0].contains("\"think\"") == think)
}

@Test("S-002 a stream that ends without a final chunk is a lost connection")
func detectsDroppedStream() async {
    let transport = ScriptedTransport(installed: [gemma])
    transport.script([#"{"message":{"role":"assistant","content":"half"},"done":false}"#])
    await #expect(throws: OllamaError.unreachable) {
        _ = try await collect(OllamaClient(transport: transport).chat(model: gemma.name, turns: [], think: false))
    }
}

@Test("S-006 unloading asks for keep_alive 0")
func unloads() async throws {
    let transport = ScriptedTransport(installed: [gemma])
    try await OllamaClient(transport: transport).unload(gemma.name)
    let request = try #require(transport.requests.last)
    #expect(request.path.hasSuffix("/api/generate"))
    #expect(request.body.contains("\"keep_alive\":0"))
}

@Test("S-011 titles use the first line, cut at a word boundary", arguments: [
    ("Fix my code\nsecond line", "Fix my code"),
    ("\n\n   spaced    out  ", "spaced out"),
    ("", "New Conversation"),
    (String(repeating: "word ", count: 30), "word word word word word word word word word word"),
])
func makesTitles(input: String, expected: String) {
    #expect(ConversationTitle.make(from: input) == expected)
}
