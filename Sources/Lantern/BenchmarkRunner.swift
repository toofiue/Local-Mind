import Foundation
import Observation
import LanternKit

/// The published test sets on this Mac.
final class BenchmarkLibrary {
    /// Replaces the files in the self-test.
    var fixture: ((BenchmarkSuite) -> Data?)?

    private var folder: URL {
        Store.url.deletingLastPathComponent().appending(path: "Benchmarks", directoryHint: .isDirectory)
    }

    private func file(_ suite: BenchmarkSuite) -> URL { folder.appending(path: suite.fileName) }

    func isDownloaded(_ suite: BenchmarkSuite) -> Bool {
        fixture?(suite) != nil || FileManager.default.fileExists(atPath: file(suite).path)
    }

    /// Fetches a file and keeps it only if it's exactly the one Lantern expects.
    func download(_ suite: BenchmarkSuite) async throws {
        let (data, _) = try await URLSession.shared.data(from: suite.downloadURL)
        guard suite.matches(data) else { throw BenchmarkDownloadError.unexpectedFile }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try data.write(to: file(suite), options: .atomic)
    }

    func items(_ suite: BenchmarkSuite) -> [BenchmarkItem] {
        rawData(suite).map { BenchmarkLoader.items(suite, from: $0) } ?? []
    }

    /// A suite's decompressed file, only if it's still exactly the verified one.
    func rawData(_ suite: BenchmarkSuite) -> Data? {
        if let data = fixture?(suite) { return data }
        guard let stored = try? Data(contentsOf: file(suite)), suite.matches(stored) else { return nil }
        return suite == .humaneval ? decompressed(file(suite)) : stored
    }

    private func decompressed(_ url: URL) -> Data {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/gunzip")
        process.arguments = ["-c", url.path]
        let output = Pipe()
        process.standardOutput = output
        guard (try? process.run()) != nil else { return Data() }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return data
    }
}

enum BenchmarkDownloadError: Error {
    case unexpectedFile
}

/// Runs a model through the published test sets, one item at a time.
@Observable
final class BenchmarkRunner {
    private(set) var modelName: String?
    private(set) var completed = 0
    private(set) var total = 0
    private(set) var currentSuite: BenchmarkSuite?

    @ObservationIgnored var onFinished: (BenchmarkReport) -> Void = { _ in }
    @ObservationIgnored var onStateChange: () -> Void = {}
    /// Runs one program in the sandbox. The self-test can replace it.
    @ObservationIgnored var runCode: @Sendable (String) async -> Bool = { program in
        await Task.detached { CodeSandbox.passes(program) }.value
    }
    @ObservationIgnored private var task: Task<Void, Never>?

    var isRunning: Bool { modelName != nil }

    func start(_ model: OllamaModel, plan: [(suite: BenchmarkSuite, items: [BenchmarkItem])], size: BenchmarkSize, client: OllamaClient) {
        guard !isRunning else { return }
        modelName = model.name
        completed = 0
        total = plan.reduce(0) { $0 + $1.items.count }
        onStateChange()
        task = Task { await run(model, plan: plan, size: size, client: client) }
    }

    func stop() {
        task?.cancel()
    }

    /// Lets the self-test wait for a run to finish.
    func wait() async {
        await task?.value
    }

    private func run(_ model: OllamaModel, plan: [(suite: BenchmarkSuite, items: [BenchmarkItem])], size: BenchmarkSize, client: OllamaClient) async {
        // A complete run takes hours, so the Mac mustn't fall asleep partway through.
        let activity = ProcessInfo.processInfo.beginActivity(options: [.idleSystemSleepDisabled, .userInitiated], reason: "Running a model benchmark")
        defer { ProcessInfo.processInfo.endActivity(activity) }
        let started = ContinuousClock.now

        for loaded in (try? await client.loadedModels()) ?? [] where loaded.name != model.name {
            try? await client.unload(loaded.name)
        }

        var suites: [BenchmarkSuiteResult] = []
        outer: for entry in plan {
            currentSuite = entry.suite
            var results: [BenchmarkItemResult] = []
            for item in entry.items {
                if Task.isCancelled {
                    suites.append(BenchmarkSuiteResult(suite: entry.suite, items: results, planned: entry.items.count))
                    break outer
                }
                results.append(await grade(item, model: model, client: client))
                completed += 1
            }
            suites.append(BenchmarkSuiteResult(suite: entry.suite, items: results, planned: entry.items.count))
        }

        let wasStopped = Task.isCancelled
        try? await client.unload(model.name)
        let scored = suites.filter { !$0.items.isEmpty }
        if !scored.isEmpty {
            let elapsed = started.duration(to: .now).components.seconds
            onFinished(BenchmarkReport(modelName: model.name, date: .now, seconds: Double(elapsed), size: size,
                                       wasStopped: wasStopped, suites: scored))
        }
        modelName = nil
        currentSuite = nil
        onStateChange()
    }

    private func grade(_ item: BenchmarkItem, model: OllamaModel, client: OllamaClient) async -> BenchmarkItemResult {
        let labCase = LabCase.plain(id: item.id, prompt: item.prompt)
        guard let response = try? await client.labComplete(model: model, labCase: labCase, maxTokens: item.suite.maxTokens) else {
            return BenchmarkItemResult(id: item.id, passed: false, reply: "", detail: "The model couldn't answer.")
        }
        let reply = response.text
        let shown = String(reply.trimmingCharacters(in: .whitespacesAndNewlines).prefix(500))
        switch item.kind {
        case .gsm8k(let answer):
            let passed = BenchmarkGrader.passesGSM8K(answer: answer, reply: reply)
            return BenchmarkItemResult(id: item.id, passed: passed, reply: shown, detail: passed ? nil : "Expected \(answer.formatted())")
        case .ifeval(let rules):
            let failed = IFEvalChecker.failedRules(rules, reply: reply)
            return BenchmarkItemResult(id: item.id, passed: failed.isEmpty, reply: shown,
                                       detail: failed.isEmpty ? nil : "Broke: \(failed.joined(separator: ", "))")
        case .humaneval(let functionPrompt, let test, let entryPoint):
            let program = BenchmarkGrader.humanEvalProgram(functionPrompt: functionPrompt, test: test, entryPoint: entryPoint, reply: reply)
            let passed = await runCode(program)
            return BenchmarkItemResult(id: item.id, passed: passed, reply: shown, detail: passed ? nil : "Failed the published unit tests")
        }
    }
}
