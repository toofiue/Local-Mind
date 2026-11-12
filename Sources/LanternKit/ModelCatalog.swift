import Foundation

/// A short list of good models to download, each described in plain words, with its real download size.
/// Sizes come from Ollama's library (2026-11). Names are Ollama tags, so `ollama pull <name>` gets the same model.
public struct CatalogModel: Sendable, Identifiable, Equatable {
    public let name: String
    public let title: String
    public let summary: String
    public let downloadBytes: Int64
    /// Images, Audio, Thinking, Tools: what the model can do.
    public let abilities: [String]

    public var id: String { name }
}

/// How well a model would run on this Mac's memory.
public enum CatalogFit: Sendable, Equatable {
    /// Leaves plenty of room for the Mac and its apps.
    case good
    /// Runs, but other apps may slow down while it's loaded.
    case tight
    /// Needs more memory than this Mac has.
    case tooBig

    public var label: String {
        switch self {
        case .good: "Runs well on this Mac"
        case .tight: "Runs, but other apps may slow down"
        case .tooBig: "Needs more memory than this Mac has"
        }
    }
}

public enum ModelCatalog {
    public static let models: [CatalogModel] = [
        CatalogModel(name: "gemma4:e4b", title: "Gemma 4", summary: "The best all-rounder. Sees images, hears audio, and thinks.",
                     downloadBytes: 6_580_000_000, abilities: ["Images", "Audio", "Thinking", "Tools"]),
        CatalogModel(name: "gemma4:e2b", title: "Gemma 4 Small", summary: "Lighter and faster. Sees images and hears audio.",
                     downloadBytes: 4_590_000_000, abilities: ["Images", "Audio", "Thinking", "Tools"]),
        CatalogModel(name: "gemma4:12b", title: "Gemma 4 12B", summary: "Smarter answers for longer work, if you have the memory.",
                     downloadBytes: 8_020_000_000, abilities: ["Images", "Thinking", "Tools"]),
        CatalogModel(name: "qwen3:8b", title: "Qwen 3", summary: "Strong at reasoning and code.",
                     downloadBytes: 5_230_000_000, abilities: ["Thinking", "Tools"]),
        CatalogModel(name: "qwen3:4b", title: "Qwen 3 Small", summary: "Quick and capable on Macs with 8 GB.",
                     downloadBytes: 2_500_000_000, abilities: ["Thinking", "Tools"]),
        CatalogModel(name: "llama3.2:3b", title: "Llama 3.2", summary: "Tiny and fast, for everyday questions.",
                     downloadBytes: 2_020_000_000, abilities: ["Tools"]),
        CatalogModel(name: "deepseek-r1:8b", title: "DeepSeek R1", summary: "Thinks step by step before answering.",
                     downloadBytes: 5_230_000_000, abilities: ["Thinking", "Tools"]),
        CatalogModel(name: "gpt-oss:20b", title: "gpt-oss", summary: "OpenAI's open model, for deep reasoning. Needs 24 GB or more.",
                     downloadBytes: 13_790_000_000, abilities: ["Thinking", "Tools"]),
        CatalogModel(name: "gemma4:26b", title: "Gemma 4 26B", summary: "The largest Gemma 4, for Macs with 32 GB or more.",
                     downloadBytes: 18_730_000_000, abilities: ["Images", "Thinking", "Tools"]),
    ]

    /// A loaded model takes about its download size, plus room to work. The Mac keeps the rest.
    public static func fit(_ model: CatalogModel, totalMemory: Int64) -> CatalogFit {
        let size = Double(model.downloadBytes), total = Double(totalMemory)
        if size <= total * 0.5 { return .good }
        if size <= total * 0.75 { return .tight }
        return .tooBig
    }

    /// The model to suggest first: the most capable one that runs well, in the list's order of preference.
    public static func recommended(totalMemory: Int64, excluding installed: Set<String> = []) -> CatalogModel? {
        models.first { fit($0, totalMemory: totalMemory) == .good && !installed.contains($0.name) }
    }

    /// Whether a catalog name is already installed. "gemma4:latest" and "gemma4" count as the same model.
    public static func isInstalled(_ name: String, in installed: [String]) -> Bool {
        installed.contains { $0 == name || $0 == name + ":latest" }
    }
}

/// Progress of a model download, decoded from Ollama's `/api/pull` stream.
public struct PullProgress: Sendable, Equatable {
    /// 0 to 1 once sizes are known.
    public var fraction: Double?
    public var completedBytes: Int64 = 0
    public var totalBytes: Int64 = 0
    /// Ollama's step, in plain words.
    public var step: String
    public var isDone = false

    public init(fraction: Double? = nil, completedBytes: Int64 = 0, totalBytes: Int64 = 0, step: String, isDone: Bool = false) {
        self.fraction = fraction
        self.completedBytes = completedBytes
        self.totalBytes = totalBytes
        self.step = step
        self.isDone = isDone
    }
}

public struct PullDecoder: Sendable {
    private var totals: [String: Int64] = [:]
    private var completed: [String: Int64] = [:]

    public init() {}

    private struct Line: Decodable {
        let status: String?
        let digest: String?
        let total: Int64?
        let completed: Int64?
        let error: String?
    }

    /// The progress after one line, or an error Ollama reported.
    public mutating func decode(_ text: String) throws -> PullProgress? {
        guard let data = text.data(using: .utf8), let line = try? JSONDecoder().decode(Line.self, from: data) else { return nil }
        if let error = line.error { throw OllamaError.server(error) }
        let status = line.status ?? ""
        if let digest = line.digest, let total = line.total, total > 0 {
            totals[digest] = total
            completed[digest] = line.completed ?? completed[digest] ?? 0
        }
        let total = totals.values.reduce(0, +), done = completed.values.reduce(0, +)
        var progress = PullProgress(fraction: total > 0 ? min(1, Double(done) / Double(total)) : nil,
                                    completedBytes: done, totalBytes: total, step: Self.plain(status))
        if status == "success" {
            progress.isDone = true
            progress.fraction = 1
        }
        return progress
    }

    static func plain(_ status: String) -> String {
        switch true {
        case status.hasPrefix("pulling manifest"): "Starting"
        case status.hasPrefix("pulling"), status.hasPrefix("downloading"): "Downloading"
        case status.hasPrefix("verifying"): "Checking the download"
        case status.hasPrefix("writing"), status.hasPrefix("removing"): "Finishing"
        case status == "success": "Done"
        default: status.isEmpty ? "Downloading" : status.prefix(1).uppercased() + status.dropFirst()
        }
    }
}

extension OllamaClient {
    /// Downloads a model, reporting progress as it goes. Ollama resumes an interrupted download.
    public func pull(_ name: String) -> AsyncThrowingStream<PullProgress, Error> {
        struct Body: Encodable { let model: String; let stream: Bool }
        let lines = transport.lines(post("api/pull", Body(model: name, stream: true)))
        return AsyncThrowingStream { continuation in
            let task = Task {
                var decoder = PullDecoder()
                do {
                    for try await line in lines {
                        if let progress = try decoder.decode(line) {
                            continuation.yield(progress)
                            if progress.isDone { break }
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// Removes a model from this Mac.
    public func delete(_ name: String) async throws {
        struct Body: Encodable { let model: String }
        var request = post("api/delete", Body(model: name))
        request.httpMethod = "DELETE"
        _ = try await transport.send(request)
    }
}
