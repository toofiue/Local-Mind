import Foundation
import Testing
@testable import LanternKit

@Test("S-027 loaded models and their memory come from Ollama")
func readsLoaded() async throws {
    let transport = ScriptedTransport(installed: [])
    transport.setLoaded(["a:1", "b:2"])
    let loaded = try await OllamaClient(transport: transport).loadedModels()
    #expect(loaded == [LoadedModel(name: "a:1", memory: 1_000), LoadedModel(name: "b:2", memory: 1_000)])
}

@Test("S-027 capabilities read in plain words, in a fixed order")
func summarizesCapabilities() {
    let model = OllamaModel(name: "m", size: 1, capabilities: ["tools", "completion", "thinking", "audio", "vision"])
    #expect(model.capabilitySummary == "Images, Audio, Thinking, Tools")
    #expect(OllamaModel(name: "m", size: 1, capabilities: ["completion"]).capabilitySummary.isEmpty)
}

@Test("S-028 unloading removes the model from memory")
func unloadsModel() async throws {
    let transport = ScriptedTransport(installed: [])
    transport.setLoaded(["a:1"])
    let client = OllamaClient(transport: transport)
    try await client.unload("a:1")
    #expect(try await client.loadedModels().isEmpty)
}

@Test("S-029 the keep-loaded time goes with each request")
func sendsKeepAlive() async throws {
    let transport = ScriptedTransport(installed: [])
    transport.script(ScriptedTransport.reply(text: ["ok"]))
    for try await _ in OllamaClient(transport: transport).chat(model: "m", turns: [], think: false, keepAlive: "15m") {}
    #expect(transport.chatBodies[0].contains("\"keep_alive\":\"15m\""))
}

private let small = OllamaModel(name: "small:1", size: 10)
private let large = OllamaModel(name: "large:1", size: 100)

@Test("S-031 the chosen model wins")
func usesChosenModel() {
    #expect(DefaultModel.resolve(chosen: "large:1", remembered: "small:1", installed: [small, large]) == "large:1")
}

@Test("S-031 a removed choice falls back to the last used")
func fallsBackToRemembered() {
    #expect(DefaultModel.resolve(chosen: "gone:1", remembered: "large:1", installed: [small, large]) == "large:1")
}

@Test("S-031 with nothing to go on, the smallest is used")
func fallsBackToSmallest() {
    #expect(DefaultModel.resolve(chosen: "", remembered: "gone:1", installed: [large, small]) == "small:1")
    #expect(DefaultModel.resolve(chosen: "", remembered: nil, installed: []) == nil)
}
