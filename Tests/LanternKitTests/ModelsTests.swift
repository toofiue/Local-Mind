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
