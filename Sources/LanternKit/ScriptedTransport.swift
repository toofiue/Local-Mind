import Foundation
import os

/// A stand-in for Ollama used by unit tests and the app's self-test, so they
/// run without a model. It records every request and replays scripted lines.
public final class ScriptedTransport: OllamaTransport {
    public struct Recorded: Sendable {
        public let path: String
        public let body: String
    }

    private struct State {
        var installed: [OllamaModel] = []
        var loaded: [String] = []
        var chatLines: [String] = []
        var delay: Duration = .zero
        var isDown = false
        var requests: [Recorded] = []
        var labReply: (@Sendable (String) -> String)?
    }

    private let state = OSAllocatedUnfairLock(initialState: State())

    public init(installed: [OllamaModel]) {
        state.withLock { $0.installed = installed }
    }

    public var requests: [Recorded] { state.withLock(\.requests) }
    public var chatBodies: [String] { requests.filter { $0.path.hasSuffix("/api/chat") }.map(\.body) }

    public func setLoaded(_ names: [String]) { state.withLock { $0.loaded = names } }
    /// Answers non-streaming Lab requests. The closure gets the request body and returns the reply text.
    public func scriptLab(_ reply: @escaping @Sendable (String) -> String) { state.withLock { $0.labReply = reply } }

    public func setDown(_ down: Bool) { state.withLock { $0.isDown = down } }

    public func script(_ lines: [String], delay: Duration = .zero) {
        state.withLock {
            $0.chatLines = lines
            $0.delay = delay
        }
    }

    /// A chat stream of thinking chunks, then text chunks, then the final chunk.
    public static func reply(thinking: [String] = [], text: [String]) -> [String] {
        func line(_ field: String, _ value: String) -> String {
            let escaped = String(data: try! JSONEncoder().encode(value), encoding: .utf8)!
            return #"{"message":{"role":"assistant","content":"","\#(field)":\#(escaped)},"done":false}"#
                .replacingOccurrences(of: #""content":"","content":"#, with: #""content":"#)
        }
        return thinking.map { line("thinking", $0) } + text.map { line("content", $0) }
            + [#"{"message":{"role":"assistant","content":""},"done":true,"eval_count":40,"eval_duration":2000000000}"#]
    }

    private func record(_ request: URLRequest) -> Bool {
        state.withLock {
            let body = request.httpBody.flatMap { String(data: $0, encoding: .utf8) } ?? ""
            $0.requests.append(Recorded(path: request.url?.path ?? "", body: body))
            return $0.isDown
        }
    }

    public func send(_ request: URLRequest) async throws -> Data {
        if record(request) { throw OllamaError.unreachable }
        let path = request.url?.path ?? ""
        return try state.withLock { state in
            func encode(_ value: Any) throws -> Data { try JSONSerialization.data(withJSONObject: value) }
            if path.hasSuffix("/api/tags") {
                return try encode(["models": state.installed.map {
                    ["name": $0.name, "size": $0.size, "details": ["runner": "mlx"]] as [String: Any]
                }])
            }
            if path.hasSuffix("/api/ps") {
                return try encode(["models": state.loaded.map { ["name": $0, "size": 1_000] as [String: Any] }])
            }
            if path.hasSuffix("/api/show") {
                let asked = (try? JSONSerialization.jsonObject(with: request.httpBody ?? Data())) as? [String: Any]
                let model = state.installed.first { $0.name == asked?["model"] as? String }
                return try encode(["capabilities": Array(model?.capabilities ?? []),
                                   "model_info": ["test.context_length": model?.contextLimit ?? 0]] as [String: Any])
            }
            if path.hasSuffix("/api/chat"), let reply = state.labReply {
                let body = request.httpBody.flatMap { String(data: $0, encoding: .utf8) } ?? ""
                var message: [String: Any] = ["role": "assistant", "content": reply(body)]
                if body.contains(ModelLab.weatherToolName) {
                    message["tool_calls"] = [["function": ["name": ModelLab.weatherToolName, "arguments": ["city": "Paris"]]]]
                }
                return try encode(["message": message, "done": true, "eval_count": 40, "eval_duration": 2_000_000_000, "load_duration": 3_000_000_000] as [String: Any])
            }
            if path.hasSuffix("/api/generate") {
                let asked = (try? JSONSerialization.jsonObject(with: request.httpBody ?? Data())) as? [String: Any]
                state.loaded.removeAll { $0 == asked?["model"] as? String }
                return Data("{}".utf8)
            }
            if path.hasSuffix("/api/delete") {
                let asked = (try? JSONSerialization.jsonObject(with: request.httpBody ?? Data())) as? [String: Any]
                state.installed.removeAll { $0.name == asked?["model"] as? String }
                return Data("{}".utf8)
            }
            throw OllamaError.server("no script for \(path)")
        }
    }

    public func lines(_ request: URLRequest) -> AsyncThrowingStream<String, Error> {
        let down = record(request)
        let (lines, delay) = state.withLock { ($0.chatLines, $0.delay) }
        return AsyncThrowingStream { continuation in
            let task = Task {
                if down {
                    continuation.finish(throwing: OllamaError.unreachable)
                    return
                }
                for line in lines {
                    if delay > .zero { try? await Task.sleep(for: delay) }
                    if Task.isCancelled { break }
                    continuation.yield(line)
                }
                // A finished download installs the model, as Ollama does.
                if request.url?.path.hasSuffix("/api/pull") == true, !Task.isCancelled, lines.contains(where: { $0.contains("\"success\"") }),
                   let asked = (try? JSONSerialization.jsonObject(with: request.httpBody ?? Data())) as? [String: Any],
                   let name = asked["model"] as? String {
                    state.withLock { $0.installed.append(OllamaModel(name: name, size: 1)) }
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
