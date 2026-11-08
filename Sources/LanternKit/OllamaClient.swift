import Foundation

/// A model installed in Ollama.
public struct OllamaModel: Sendable, Equatable, Identifiable {
    public let name: String
    public let size: Int64
    public var capabilities: Set<String>

    public var id: String { name }
    public var supportsThinking: Bool { capabilities.contains("thinking") }

    public init(name: String, size: Int64, capabilities: Set<String> = []) {
        self.name = name
        self.size = size
        self.capabilities = capabilities
    }
}

/// A model in memory right now.
public struct LoadedModel: Sendable, Equatable {
    public let name: String
    public let memory: Int64

    public init(name: String, memory: Int64) {
        self.name = name
        self.memory = memory
    }
}

/// One message in the history sent to the model.
public struct ChatTurn: Sendable, Equatable, Encodable {
    public let role: String
    public let content: String

    public init(role: String, content: String) {
        self.role = role
        self.content = content
    }
}

public enum ChatEvent: Sendable, Equatable {
    case thinking(String)
    case text(String)
    case done(tokensPerSecond: Double?)
}

public enum OllamaError: Error, Equatable {
    /// Nothing answered at Ollama's address, or the connection dropped.
    case unreachable
    /// Ollama answered with an error message.
    case server(String)
}

/// The network underneath the client. Tests replace it with `ScriptedTransport`.
public protocol OllamaTransport: Sendable {
    func send(_ request: URLRequest) async throws -> Data
    func lines(_ request: URLRequest) -> AsyncThrowingStream<String, Error>
}

public struct URLSessionTransport: OllamaTransport {
    public init() {}

    public func send(_ request: URLRequest) async throws -> Data {
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, http.statusCode >= 400 {
                throw OllamaError.server(ChatStreamDecoder.errorMessage(in: data) ?? "HTTP \(http.statusCode)")
            }
            return data
        } catch let error as URLError {
            throw error.code == .cancelled ? CancellationError() : OllamaError.unreachable
        }
    }

    public func lines(_ request: URLRequest) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let (bytes, _) = try await URLSession.shared.bytes(for: request)
                    for try await line in bytes.lines { continuation.yield(line) }
                    continuation.finish()
                } catch let error as URLError {
                    continuation.finish(throwing: error.code == .cancelled ? CancellationError() : OllamaError.unreachable)
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}

/// Turns the newline-delimited JSON from `/api/chat` into events.
public enum ChatStreamDecoder {
    private struct Chunk: Decodable {
        struct Body: Decodable {
            let content: String?
            let thinking: String?
        }
        let message: Body?
        let done: Bool?
        let eval_count: Int?
        let eval_duration: Int64?
        let error: String?
    }

    public static func decode(_ line: String) throws -> [ChatEvent] {
        guard let chunk = try? JSONDecoder().decode(Chunk.self, from: Data(line.utf8)) else { return [] }
        if let error = chunk.error { throw OllamaError.server(error) }
        var events: [ChatEvent] = []
        if let thinking = chunk.message?.thinking, !thinking.isEmpty { events.append(.thinking(thinking)) }
        if let content = chunk.message?.content, !content.isEmpty { events.append(.text(content)) }
        if chunk.done == true {
            var speed: Double?
            if let count = chunk.eval_count, let duration = chunk.eval_duration, duration > 0 {
                speed = Double(count) / (Double(duration) / 1_000_000_000)
            }
            events.append(.done(tokensPerSecond: speed))
        }
        return events
    }

    static func errorMessage(in data: Data) -> String? {
        (try? JSONDecoder().decode(Chunk.self, from: data))?.error
    }
}

/// The conversation history a request carries: every turn, in order, minus replies with no text.
public enum ChatHistory {
    public static func turns(_ all: [ChatTurn]) -> [ChatTurn] {
        all.filter { !$0.content.isEmpty }
    }
}

public struct OllamaClient: Sendable {
    public static let defaultBase = URL(string: "http://127.0.0.1:11434")!

    let base: URL
    let transport: any OllamaTransport

    public init(base: URL = OllamaClient.defaultBase, transport: any OllamaTransport = URLSessionTransport()) {
        self.base = base
        self.transport = transport
    }

    /// Every installed model with its capabilities.
    public func models() async throws -> [OllamaModel] {
        struct Tags: Decodable {
            struct Row: Decodable { let name: String; let size: Int64 }
            let models: [Row]
        }
        struct Show: Decodable { let capabilities: [String]? }

        let tags = try JSONDecoder().decode(Tags.self, from: try await transport.send(get("api/tags")))
        var result: [OllamaModel] = []
        for row in tags.models {
            let data = try await transport.send(post("api/show", ["model": row.name]))
            let show = try JSONDecoder().decode(Show.self, from: data)
            result.append(OllamaModel(name: row.name, size: row.size, capabilities: Set(show.capabilities ?? [])))
        }
        return result
    }

    /// The models in memory right now.
    public func loadedModels() async throws -> [LoadedModel] {
        struct Running: Decodable {
            struct Row: Decodable { let name: String; let size: Int64 }
            let models: [Row]
        }
        // Ollama can be slow to answer this while it loads or unloads a model.
        var request = get("api/ps")
        request.timeoutInterval = 60
        let running = try JSONDecoder().decode(Running.self, from: try await transport.send(request))
        return running.models.map { LoadedModel(name: $0.name, memory: $0.size) }
    }

    public func unload(_ name: String) async throws {
        struct Body: Encodable { let model: String; let keep_alive: Int }
        _ = try await transport.send(post("api/generate", Body(model: name, keep_alive: 0)))
    }

    /// Streams one reply. Ending the consumer's task ends the request.
    public func chat(model: String, turns: [ChatTurn], think: Bool) -> AsyncThrowingStream<ChatEvent, Error> {
        struct Body: Encodable {
            let model: String
            let messages: [ChatTurn]
            let stream: Bool
            let think: Bool?
        }
        var request = post("api/chat", Body(model: model, messages: turns, stream: true, think: think ? true : nil))
        // A cold model can take a while to send its first byte.
        request.timeoutInterval = 600
        let lines = transport.lines(request)
        return AsyncThrowingStream { continuation in
            let task = Task {
                var finished = false
                do {
                    for try await line in lines {
                        for event in try ChatStreamDecoder.decode(line) {
                            if case .done = event { finished = true }
                            continuation.yield(event)
                        }
                    }
                    if finished || Task.isCancelled {
                        continuation.finish()
                    } else {
                        continuation.finish(throwing: OllamaError.unreachable)
                    }
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func get(_ path: String) -> URLRequest {
        var request = URLRequest(url: base.appending(path: path))
        request.timeoutInterval = 5
        return request
    }

    private func post(_ path: String, _ body: some Encodable) -> URLRequest {
        var request = URLRequest(url: base.appending(path: path))
        request.httpMethod = "POST"
        request.httpBody = try? JSONEncoder().encode(body)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 30
        return request
    }
}
