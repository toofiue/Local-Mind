import CryptoKit
import Foundation

/// A published test set, pinned to the exact file Lantern has verified.
public enum BenchmarkSuite: String, Codable, CaseIterable, Sendable, Identifiable {
    case gsm8k, ifeval, humaneval

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .gsm8k: "GSM8K"
        case .ifeval: "IFEval"
        case .humaneval: "HumanEval"
        }
    }

    public var measures: String {
        switch self {
        case .gsm8k: "Multi-step grade-school math word problems."
        case .ifeval: "Following instructions a program can check, like word counts and formats."
        case .humaneval: "Writing Python functions that must pass unit tests."
        }
    }

    public var scoring: String {
        switch self {
        case .gsm8k: "The final number must exactly match the published answer."
        case .ifeval: "Strict scoring: every instruction in a prompt must be met. Language and sentence checks use Apple's detectors instead of IFEval's Python libraries, so a few results can differ."
        case .humaneval: "The function runs against the published unit tests and must pass all of them."
        }
    }

    public var downloadURL: URL {
        switch self {
        case .gsm8k: URL(string: "https://raw.githubusercontent.com/openai/grade-school-math/master/grade_school_math/data/test.jsonl")!
        case .ifeval: URL(string: "https://raw.githubusercontent.com/google-research/google-research/master/instruction_following_eval/data/input_data.jsonl")!
        case .humaneval: URL(string: "https://raw.githubusercontent.com/openai/human-eval/master/data/HumanEval.jsonl.gz")!
        }
    }

    public var infoURL: URL {
        switch self {
        case .gsm8k: URL(string: "https://arxiv.org/abs/2110.14168")!
        case .ifeval: URL(string: "https://arxiv.org/abs/2311.07911")!
        case .humaneval: URL(string: "https://arxiv.org/abs/2107.03374")!
        }
    }

    public var fileName: String {
        switch self {
        case .gsm8k: "gsm8k.jsonl"
        case .ifeval: "ifeval.jsonl"
        case .humaneval: "humaneval.jsonl.gz"
        }
    }

    public var license: String {
        switch self {
        case .gsm8k, .humaneval: "MIT"
        case .ifeval: "Apache 2.0"
        }
    }

    public var itemCount: Int {
        switch self {
        case .gsm8k: 1_319
        case .ifeval: 541
        case .humaneval: 164
        }
    }

    public var downloadBytes: Int64 {
        switch self {
        case .gsm8k: 749_738
        case .ifeval: 207_111
        case .humaneval: 44_877
        }
    }

    /// Longest reply to allow. IFEval asks for essays of several hundred words.
    public var maxTokens: Int {
        self == .ifeval ? 1_500 : 1_000
    }

    /// Rough reply length, for estimating how long a run takes.
    public var typicalReplyTokens: Int {
        switch self {
        case .gsm8k: 150
        case .ifeval: 350
        case .humaneval: 200
        }
    }

    private var sha256: String {
        switch self {
        case .gsm8k: "3730d312f6e3440559ace48831e51066acaca737f6eabec99bccb9e4b3c39d14"
        case .ifeval: "67ffeee0fcb87c317c5b08a2de85557b4a7e96ada6178aa645b4954fe4b53d49"
        case .humaneval: "b796127e635a67f93fb35c04f4cb03cf06f38c8072ee7cee8833d7bee06979ef"
        }
    }

    /// True only for the exact file Lantern was built against.
    public func matches(_ data: Data) -> Bool {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() == sha256
    }
}

public enum BenchmarkSize: String, Codable, CaseIterable, Sendable, Identifiable {
    case sample50, sample200, complete

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .sample50: "50 per set"
        case .sample200: "200 per set"
        case .complete: "Complete sets"
        }
    }

    public func count(for suite: BenchmarkSuite) -> Int {
        switch self {
        case .sample50: min(50, suite.itemCount)
        case .sample200: min(200, suite.itemCount)
        case .complete: suite.itemCount
        }
    }
}

public struct BenchmarkItem: Sendable, Identifiable, Equatable {
    public enum Kind: Sendable, Equatable {
        case gsm8k(answer: Double)
        case ifeval(rules: [IFEvalRule])
        case humaneval(functionPrompt: String, test: String, entryPoint: String)
    }

    public let id: String
    public let suite: BenchmarkSuite
    public let prompt: String
    public let kind: Kind
}

public enum BenchmarkLoader {
    /// Reads a suite's decompressed file. Lines that don't parse are skipped.
    public static func items(_ suite: BenchmarkSuite, from data: Data) -> [BenchmarkItem] {
        let lines = String(decoding: data, as: UTF8.self).split(whereSeparator: \.isNewline)
        return lines.enumerated().compactMap { index, line in
            guard let object = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any] else { return nil }
            switch suite {
            case .gsm8k: return gsm8k(object, index: index)
            case .ifeval: return ifeval(object)
            case .humaneval: return humaneval(object)
            }
        }
    }

    private static func gsm8k(_ object: [String: Any], index: Int) -> BenchmarkItem? {
        guard let question = object["question"] as? String, let solution = object["answer"] as? String,
              let marker = solution.range(of: "####"),
              let answer = Double(solution[marker.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
                  .replacingOccurrences(of: ",", with: "")) else { return nil }
        let prompt = "Solve this problem step by step. End with a final line in the form \"Answer: <number>\".\n\n\(question)"
        return BenchmarkItem(id: "gsm8k-\(index)", suite: .gsm8k, prompt: prompt, kind: .gsm8k(answer: answer))
    }

    private static func ifeval(_ object: [String: Any]) -> BenchmarkItem? {
        guard let key = object["key"] as? Int, let prompt = object["prompt"] as? String,
              let ids = object["instruction_id_list"] as? [String],
              let arguments = object["kwargs"] as? [[String: Any]], ids.count == arguments.count else { return nil }
        let rules = zip(ids, arguments).map { IFEvalRule(id: $0, arguments: $1.compactMapValues(IFEvalRule.Value.init)) }
        return BenchmarkItem(id: "ifeval-\(key)", suite: .ifeval, prompt: prompt, kind: .ifeval(rules: rules))
    }

    private static func humaneval(_ object: [String: Any]) -> BenchmarkItem? {
        guard let task = object["task_id"] as? String, let function = object["prompt"] as? String,
              let test = object["test"] as? String, let entryPoint = object["entry_point"] as? String else { return nil }
        let prompt = "Complete this Python function. Reply with only the complete function in a Python code block.\n\n\(function)"
        return BenchmarkItem(id: task, suite: .humaneval, prompt: prompt,
                             kind: .humaneval(functionPrompt: function, test: test, entryPoint: entryPoint))
    }

    /// The same items for every model, so samples can be compared with each other.
    public static func sample(_ items: [BenchmarkItem], count: Int) -> [BenchmarkItem] {
        guard count < items.count else { return items }
        return Array(items.sorted { stableHash($0.id) < stableHash($1.id) }.prefix(count))
    }

    /// FNV-1a. Swift's own hashing changes between launches.
    private static func stableHash(_ text: String) -> UInt64 {
        text.utf8.reduce(14_695_981_039_346_656_037) { ($0 ^ UInt64($1)) &* 1_099_511_628_211 }
    }
}

public enum BenchmarkGrader {
    /// The number a reply gives as its final answer.
    public static func finalNumber(in reply: String) -> Double? {
        var text = reply
        if let marker = reply.range(of: "answer:", options: [.caseInsensitive, .backwards]) {
            text = String(reply[marker.upperBound...])
        }
        guard let pattern = try? NSRegularExpression(pattern: #"-?\d[\d,]*(?:\.\d+)?"#) else { return nil }
        let matches = pattern.matches(in: text, range: NSRange(text.startIndex..., in: text))
        guard let last = matches.last, let range = Range(last.range, in: text) else { return nil }
        return Double(text[range].replacingOccurrences(of: ",", with: ""))
    }

    public static func passesGSM8K(answer: Double, reply: String) -> Bool {
        guard let value = finalNumber(in: reply) else { return false }
        return abs(value - answer) < 0.000_1
    }

    /// The Python to run: the model's function, then the published tests.
    public static func humanEvalProgram(functionPrompt: String, test: String, entryPoint: String, reply: String) -> String {
        let code = extractCode(reply)
        let source: String
        if code.contains("def \(entryPoint)") {
            // The model repeated the function, so only the prompt's imports are still needed.
            let imports = functionPrompt.split(separator: "\n", omittingEmptySubsequences: false)
                .prefix { !$0.hasPrefix("def ") }.joined(separator: "\n")
            source = imports + "\n" + code
        } else {
            source = functionPrompt + code
        }
        return source + "\n\n" + test + "\n\ncheck(\(entryPoint))\n"
    }

    static func extractCode(_ reply: String) -> String {
        let lines = reply.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        guard let open = lines.firstIndex(where: { $0.trimmingCharacters(in: .whitespaces).hasPrefix("```") }) else { return reply }
        let rest = lines[(open + 1)...]
        let close = rest.firstIndex { $0.trimmingCharacters(in: .whitespaces).hasPrefix("```") } ?? rest.endIndex
        return rest[..<close].joined(separator: "\n")
    }
}

public struct BenchmarkItemResult: Codable, Sendable, Identifiable, Equatable {
    public let id: String
    public let passed: Bool
    public let reply: String
    /// Why it failed, when there's a specific reason to give.
    public var detail: String?

    public init(id: String, passed: Bool, reply: String, detail: String? = nil) {
        self.id = id
        self.passed = passed
        self.reply = reply
        self.detail = detail
    }
}

public struct BenchmarkSuiteResult: Codable, Sendable, Identifiable, Equatable {
    public let suite: BenchmarkSuite
    public var items: [BenchmarkItemResult]
    /// How many items this run set out to do.
    public let planned: Int

    public var id: BenchmarkSuite { suite }

    public init(suite: BenchmarkSuite, items: [BenchmarkItemResult], planned: Int) {
        self.suite = suite
        self.items = items
        self.planned = planned
    }

    public var passed: Int { items.filter(\.passed).count }
    public var share: Double { items.isEmpty ? 0 : Double(passed) / Double(items.count) }

    /// Only a complete, unstopped run can be compared with published scores.
    public var isComplete: Bool { items.count == suite.itemCount }

    /// How far the sample's score could be from the whole set's, as a 95% margin.
    /// A Wilson interval, which stays sensible near 0% and 100%.
    public var marginOfError: Double {
        let n = Double(items.count)
        guard n > 0, !isComplete else { return 0 }
        let z = 1.96
        let denominator = 1 + z * z / n
        return z * ((share * (1 - share) / n + z * z / (4 * n * n)).squareRoot()) / denominator
    }
}

public struct BenchmarkReport: Codable, Sendable, Equatable {
    public let modelName: String
    public let date: Date
    public let seconds: Double
    public let size: BenchmarkSize
    public let wasStopped: Bool
    public let suites: [BenchmarkSuiteResult]

    public init(modelName: String, date: Date, seconds: Double, size: BenchmarkSize, wasStopped: Bool, suites: [BenchmarkSuiteResult]) {
        self.modelName = modelName
        self.date = date
        self.seconds = seconds
        self.size = size
        self.wasStopped = wasStopped
        self.suites = suites
    }
}

public enum BenchmarkEstimate {
    /// Minutes a run should take, from this model's measured speed.
    public static func minutes(size: BenchmarkSize, suites: [BenchmarkSuite], tokensPerSecond: Double) -> Int {
        guard tokensPerSecond > 0 else { return 0 }
        let seconds = suites.reduce(0.0) { total, suite in
            total + Double(size.count(for: suite)) * (Double(suite.typicalReplyTokens) / tokensPerSecond + 1.5)
        }
        return max(1, Int((seconds / 60).rounded()))
    }
}
