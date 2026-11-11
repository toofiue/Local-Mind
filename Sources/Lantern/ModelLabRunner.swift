import Foundation
import Observation
import LanternKit

/// Runs one model through the Lab, one test at a time.
@Observable
final class ModelLabRunner {
    private(set) var modelName: String?
    private(set) var completed = 0
    private(set) var total = 0
    private(set) var currentTest = ""

    @ObservationIgnored var onFinished: (LabReport) -> Void = { _ in }
    @ObservationIgnored var onStateChange: () -> Void = {}
    /// Makes the spoken clips. The self-test replaces it.
    @ObservationIgnored var renderAudio: @Sendable () async -> [String: String] = {
        await Task.detached { LabAudioRenderer.render() }.value
    }
    @ObservationIgnored private var task: Task<Void, Never>?

    var isRunning: Bool { modelName != nil }

    func start(_ model: OllamaModel, client: OllamaClient, totalMemory: Int64, swapUsed: @escaping () -> Int64) {
        guard !isRunning else { return }
        modelName = model.name
        completed = 0
        total = ModelLab.cases(for: model).count + (model.supportsAudio ? LabAudio.clips.count : 0)
        currentTest = model.supportsAudio ? "Preparing audio" : ""
        onStateChange()
        let renderAudio = self.renderAudio
        task = Task {
            let audio = model.supportsAudio ? await renderAudio() : [:]
            let cases = ModelLab.cases(for: model, audio: audio)
            total = cases.count
            await run(model, cases: cases, client: client, totalMemory: totalMemory, swapUsed: swapUsed)
        }
    }

    func stop() {
        task?.cancel()
    }

    /// Lets the self-test wait for a run to finish.
    func wait() async {
        await task?.value
    }

    private func run(_ model: OllamaModel, cases: [LabCase], client: OllamaClient, totalMemory: Int64, swapUsed: () -> Int64) async {
        let swapBefore = swapUsed()
        // Start empty, so the load time and memory are this model's alone.
        for loaded in (try? await client.loadedModels()) ?? [] { try? await client.unload(loaded.name) }

        var results: [LabCaseResult] = []
        var tokensPerSecond = 0.0
        var loadSeconds = 0.0
        var memory: Int64 = 0
        var swapAfter = swapBefore

        for labCase in cases {
            if Task.isCancelled { break }
            currentTest = "\(labCase.area.title): \(labCase.name)"
            do {
                let response = try await client.labComplete(model: model, labCase: labCase, maxTokens: labCase.maxTokens)
                if labCase.area == .speed {
                    tokensPerSecond = response.tokensPerSecond
                    loadSeconds = response.loadSeconds
                }
                if memory == 0, let loaded = try? await client.loadedModels().first(where: { $0.name == model.name }) {
                    memory = loaded.memory
                }
                swapAfter = max(swapAfter, swapUsed())
                results.append(LabCaseResult(id: labCase.id, area: labCase.area, name: labCase.name,
                                             reply: replySummary(response, for: labCase), passed: labCase.grade(response),
                                             documentTokens: labCase.documentTokens,
                                             prompt: labCase.shownPrompt, expected: labCase.expected))
            } catch is CancellationError {
                break
            } catch {
                results.append(LabCaseResult(id: labCase.id, area: labCase.area, name: labCase.name,
                                             reply: "The model couldn't answer this test.", passed: false,
                                             documentTokens: labCase.documentTokens,
                                             prompt: labCase.shownPrompt, expected: labCase.expected))
            }
            completed += 1
        }

        let wasStopped = Task.isCancelled
        // A test run shouldn't leave a big model sitting in memory.
        try? await client.unload(model.name)
        if !wasStopped {
            onFinished(LabReport(modelName: model.name, date: .now, tokensPerSecond: tokensPerSecond, loadSeconds: loadSeconds,
                                 memoryBytes: memory, swapGrowthBytes: swapAfter - swapBefore, totalMemoryBytes: totalMemory,
                                 supportsImages: model.supportsImages, supportsTools: model.capabilities.contains("tools"),
                                 results: results, supportsAudio: model.supportsAudio))
        }
        modelName = nil
        currentTest = ""
        onStateChange()
    }

    private func replySummary(_ response: LabResponse, for labCase: LabCase) -> String {
        if labCase.area == .audio, labCase.audioBase64 != nil, let clip = LabAudio.clips.first(where: { $0.id == labCase.id }), clip.isTranscript {
            let errors = LabAudio.wordErrorRate(reference: clip.script, hypothesis: response.text)
            let right = max(0, Int(((1 - errors) * 100).rounded()))
            return "\(right)% of words right. " + String(response.text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(300))
        }
        return replySummary(response)
    }

    private func replySummary(_ response: LabResponse) -> String {
        if let call = response.toolCalls.first {
            let arguments = call.arguments.map { "\($0.key): \($0.value)" }.sorted().joined(separator: ", ")
            return "Called \(call.name) (\(arguments))"
        }
        return String(response.text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(400))
    }
}
