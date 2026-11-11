import CoreGraphics
import CoreText
import Foundation
import ImageIO
import UniformTypeIdentifiers

public enum LabArea: String, Codable, CaseIterable, Sendable, Identifiable {
    case speed, reasoning, code, instructions, data, documents, images, audio, tools

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .speed: "Speed"
        case .reasoning: "Reasoning"
        case .code: "Coding"
        case .instructions: "Following Instructions"
        case .data: "Structured Data"
        case .documents: "Long Documents"
        case .images: "Images"
        case .audio: "Listening"
        case .tools: "Using Tools"
        }
    }
}

/// A published way of testing models that an area is based on.
public struct LabStandard: Sendable, Equatable {
    public let name: String
    public let url: URL
    /// How closely Lantern follows it.
    public let relation: String
}

public enum LabRating: String, Sendable {
    case strong = "Strong", fair = "Fair", weak = "Weak"

    public init(share: Double) {
        self = share >= 0.8 ? .strong : share >= 0.5 ? .fair : .weak
    }
}

extension LabArea {
    /// What this area tells you about a model.
    public var measures: String {
        switch self {
        case .speed: "How quickly the model loads and writes on this Mac."
        case .reasoning: "Whether it can work through short math and logic problems."
        case .code: "Whether it can read code, spot a bug, and write a small function."
        case .instructions: "Whether it obeys exact rules about format and length."
        case .data: "Whether it can return valid JSON that other software can read."
        case .documents: "Whether it still remembers facts placed at the start, middle, and end of long text."
        case .images: "Whether it can see a picture at all."
        case .audio: "How accurately it transcribes speech, across voices and lengths, and whether it understands what it hears."
        case .tools: "Whether it calls a tool correctly instead of guessing the answer."
        }
    }

    /// How a reply in this area is scored.
    public var scoring: String {
        switch self {
        case .speed: "Ollama's own counters: tokens written divided by generation time. Lantern calls 25 or more per second fast, 10 or more usable, and less than that slow."
        case .reasoning: "Pass only if the final number or name exactly matches the known answer."
        case .code: "Reading tests must match the known output. The written function is checked by pattern. Lantern never runs code a model wrote."
        case .instructions: "A fixed rule checks the reply, such as counting its lines or words."
        case .data: "The reply must parse as JSON and contain the right values."
        case .documents: "Pass only if all three hidden facts come back correctly."
        case .images: "Lantern draws the picture itself, so the right answer is known exactly."
        case .audio: "macOS reads known text aloud. A transcript passes if at most 15% of its words are wrong, counting wrong, missing, and extra words. Numbers are left out, so how a model writes them can't count against it."
        case .tools: "Pass only if the model calls the right tool with the right argument."
        }
    }

    public var standard: LabStandard? {
        func standard(_ name: String, _ link: String, _ relation: String) -> LabStandard? {
            URL(string: link).map { LabStandard(name: name, url: $0, relation: relation) }
        }
        switch self {
        case .speed:
            return standard("llama-bench", "https://github.com/ggml-org/llama.cpp/tree/master/tools/llama-bench", "Same measure: generated tokens per second.")
        case .reasoning:
            return standard("GSM8K", "https://arxiv.org/abs/2110.14168", "Modeled on it: short problems with one known answer. Five items of Lantern's own, not its dataset.")
        case .code:
            return standard("HumanEval", "https://arxiv.org/abs/2107.03374", "Lighter than it. HumanEval runs code against unit tests, and Lantern doesn't run model-written code.")
        case .instructions:
            return standard("IFEval", "https://arxiv.org/abs/2311.07911", "Same method: rules a program can verify. Four kinds of rule, out of IFEval's 25.")
        case .data:
            return standard("IFEval", "https://arxiv.org/abs/2311.07911", "Same method as IFEval's JSON format rule.")
        case .documents:
            return standard("Needle in a Haystack", "https://github.com/gkamradt/LLMTest_NeedleInAHaystack", "Same method: facts hidden in long filler text, at growing lengths.")
        case .images:
            return nil
        case .audio:
            return standard("Open ASR Leaderboard", "https://huggingface.co/spaces/hf-audio/open_asr_leaderboard", "Same measure: word error rate. Lantern's clips are read by macOS voices, which are clearer than real recordings.")
        case .tools:
            return standard("Berkeley Function Calling Leaderboard", "https://gorilla.cs.berkeley.edu/leaderboard.html", "Modeled on it: right function, right arguments. One call, not its full set.")
        }
    }
}

public struct LabToolCall: Sendable, Equatable {
    public let name: String
    public let arguments: [String: String]

    public init(name: String, arguments: [String: String]) {
        self.name = name
        self.arguments = arguments
    }
}

/// One finished reply from a test.
public struct LabResponse: Sendable, Equatable {
    public let text: String
    public let toolCalls: [LabToolCall]
    public let loadSeconds: Double
    public let tokensPerSecond: Double

    public init(text: String, toolCalls: [LabToolCall] = [], loadSeconds: Double = 0, tokensPerSecond: Double = 0) {
        self.text = text
        self.toolCalls = toolCalls
        self.loadSeconds = loadSeconds
        self.tokensPerSecond = tokensPerSecond
    }
}

/// One test: what to ask, and the fixed rule that grades the reply.
public struct LabCase: Sendable, Identifiable {
    public let id: String
    public let area: LabArea
    public let name: String
    public let prompt: String
    public var imageBase64: String?
    public var usesTool = false
    public var documentTokens: Int?
    /// A short stand-in for a prompt too long to show.
    public var promptSummary: String?
    /// 16 kHz WAV, sent the same way as images.
    public var audioBase64: String?
    /// Longest reply to allow. Transcripts of long recordings need more.
    public var maxTokens = 800
    /// The answer or rule the reply is graded against, in plain words.
    public let expected: String
    public let grade: @Sendable (LabResponse) -> Bool

    public var shownPrompt: String { promptSummary ?? prompt }

    /// A bare request for a benchmark question, which is graded separately.
    public static func plain(id: String, prompt: String) -> LabCase {
        LabCase(id: id, area: .reasoning, name: id, prompt: prompt, expected: "", grade: { _ in true })
    }
}

enum LabGrade {
    static func lastNumber(_ text: String) -> Int? {
        let digits = text.replacingOccurrences(of: ",", with: "")
            .split { !$0.isNumber }
        return digits.last.flatMap { Int($0) }
    }

    static func number(_ expected: Int) -> @Sendable (LabResponse) -> Bool {
        { lastNumber($0.text) == expected }
    }

    static func words(_ text: String) -> [String] {
        text.lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init)
    }

    static func hasWord(_ word: String) -> @Sendable (LabResponse) -> Bool {
        { words($0.text).contains(word) }
    }

    /// Models often wrap JSON in a code fence, which is still usable.
    static func json(_ text: String) -> Any? {
        let lines = text.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: "\n", omittingEmptySubsequences: false)
        let body = lines.filter { !$0.hasPrefix("```") }.joined(separator: "\n")
        return try? JSONSerialization.jsonObject(with: Data(body.utf8))
    }
}

public enum ModelLab {
    public static let weatherToolName = "get_weather"

    /// The tests that apply to this model, cheapest first.
    /// `audio` holds each clip's WAV by clip id, made by the app, since it takes macOS's voices.
    public static func cases(for model: OllamaModel, audio: [String: String] = [:]) -> [LabCase] {
        var cases = baseCases
        var sizes = [2_000, 8_000]
        if model.contextLimit >= 20_000 { sizes.append(20_000) }
        cases += sizes.map(documentCase)
        if model.supportsImages { cases += imageCases }
        if model.supportsAudio {
            cases += LabAudio.clips.compactMap { clip in audio[clip.id].map { LabAudio.labCase(clip, audioBase64: $0) } }
        }
        if model.capabilities.contains("tools") { cases.append(toolCase) }
        return cases
    }

    private static let baseCases: [LabCase] = [
        LabCase(id: "speed", area: .speed, name: "Write a paragraph", prompt: "Write one short paragraph about the ocean.",
                expected: "Any complete reply. Speed is measured, not graded.", grade: { !$0.text.isEmpty && $0.tokensPerSecond > 0 }),

        LabCase(id: "r-sheep", area: .reasoning, name: "Trick question",
                prompt: "A farmer has 17 sheep. All but 9 run away. How many sheep are left? Reply with only the number.",
                expected: "9", grade: LabGrade.number(9)),
        LabCase(id: "r-machines", area: .reasoning, name: "Rates",
                prompt: "If 3 machines make 3 widgets in 3 minutes, how many minutes do 100 machines take to make 100 widgets? Reply with only the number.",
                expected: "3", grade: LabGrade.number(3)),
        LabCase(id: "r-multiply", area: .reasoning, name: "Arithmetic",
                prompt: "What is 37 times 43? Reply with only the number.", expected: "1591", grade: LabGrade.number(1_591)),
        LabCase(id: "r-sequence", area: .reasoning, name: "Number pattern",
                prompt: "What number comes next: 2, 6, 12, 20, 30? Reply with only the number.", expected: "42", grade: LabGrade.number(42)),
        LabCase(id: "r-shortest", area: .reasoning, name: "Logic",
                prompt: "Anna is taller than Ben. Ben is taller than Cara. Who is the shortest? Reply with only the name.",
                expected: "Cara", grade: LabGrade.hasWord("cara")),

        LabCase(id: "c-sum", area: .code, name: "Read Python",
                prompt: "What does this Python print? Reply with only the output.\n\nprint(sum(i * i for i in range(4)))",
                expected: "14", grade: LabGrade.number(14)),
        LabCase(id: "c-reverse", area: .code, name: "Read string slicing",
                prompt: "What does this Python print? Reply with only the output.\n\nprint(\"lantern\"[::-1][:3])",
                expected: "nre", grade: LabGrade.hasWord("nre")),
        LabCase(id: "c-sort", area: .code, name: "Read Swift",
                prompt: "What does this Swift print? Reply with only the output.\n\nprint([3, 1, 2].sorted()[1])",
                expected: "2", grade: LabGrade.number(2)),
        LabCase(id: "c-bug", area: .code, name: "Find a bug",
                prompt: "This code should print the sum of the list. Which line number has the bug? Reply with only the number.\n\n1: total = 0\n2: for n in [1, 2, 3]:\n3:     total = n\n4: print(total)",
                expected: "3", grade: LabGrade.number(3)),
        LabCase(id: "c-write", area: .code, name: "Write a function",
                prompt: "Write a Python function named is_even that returns True when n is even. Reply with only the code.",
                expected: "A function named is_even that checks n % 2", grade: { reply in
                    let compact = reply.text.replacingOccurrences(of: " ", with: "")
                    return compact.contains("defis_even") && (compact.contains("%2") || compact.contains("&1"))
                }),

        LabCase(id: "i-bullets", area: .instructions, name: "Exact format",
                prompt: "List three fruits as exactly three lines, each starting with \"- \". Write nothing else.",
                expected: "Exactly three lines, each starting with \"- \"", grade: { reply in
                    let lines = reply.text.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
                    return lines.count == 3 && lines.allSatisfy { $0.hasPrefix("- ") }
                }),
        LabCase(id: "i-short", area: .instructions, name: "Length limit",
                prompt: "Describe a lantern in fewer than 12 words. Use the word lantern.",
                expected: "Fewer than 12 words, including \"lantern\"", grade: { reply in
                    let words = LabGrade.words(reply.text)
                    return words.count < 12 && words.contains("lantern")
                }),
        LabCase(id: "i-caps", area: .instructions, name: "Capitals only",
                prompt: "Say good morning in all capital letters.",
                expected: "Every letter capitalized", grade: { reply in
                    let letters = reply.text.filter(\.isLetter)
                    return !letters.isEmpty && letters == letters.uppercased()
                }),
        LabCase(id: "i-avoid", area: .instructions, name: "Avoid a word",
                prompt: "Describe the sea in one sentence without using the word \"the\".",
                expected: "A sentence about the sea without the word \"the\"", grade: { reply in
                    let words = LabGrade.words(reply.text)
                    let onTopic = !Set(words).isDisjoint(with: ["sea", "ocean", "water", "waters", "waves", "wave", "tide", "tides", "blue", "salt"])
                    return words.count > 2 && !words.contains("the") && onTopic
                }),

        LabCase(id: "d-object", area: .data, name: "Extract to JSON",
                prompt: "Turn this into a JSON object with the keys name and age. Reply with only the JSON.\n\nMira is 34 years old.",
                expected: "Valid JSON: name is Mira, age is 34", grade: { reply in
                    guard let object = LabGrade.json(reply.text) as? [String: Any] else { return false }
                    return (object["name"] as? String)?.lowercased().contains("mira") == true && (object["age"] as? Int) == 34
                }),
        LabCase(id: "d-array", area: .data, name: "JSON list",
                prompt: "Reply with only a JSON array of the three primary colors of light, in lowercase.",
                expected: "Valid JSON: red, green, and blue", grade: { reply in
                    guard let list = LabGrade.json(reply.text) as? [String] else { return false }
                    return Set(list) == ["red", "green", "blue"]
                }),
    ]

    private static func documentCase(tokens: Int) -> LabCase {
        LabCase(id: "doc-\(tokens)", area: .documents, name: "\(tokens.formatted()) tokens",
                prompt: document(tokens: tokens), documentTokens: tokens,
                promptSummary: "A \(tokens.formatted())-token document with one fact at the start, one in the middle, and one at the end.",
                expected: "7741, harbor, and marigold",
                grade: { reply in
                    let words = LabGrade.words(reply.text)
                    return words.contains("7741") && words.contains("harbor") && words.contains("marigold")
                })
    }

    /// A long document with one fact at the start, one in the middle, and one at the end.
    /// Models often lose what's in the middle, so that position gets its own fact.
    static func document(tokens: Int) -> String {
        var body = "The secret code is 7741.\n"
        var line = 1
        var placedMiddle = false
        while body.count < tokens * 4 {
            if !placedMiddle, body.count >= tokens * 2 {
                body += "The middle word is harbor.\n"
                placedMiddle = true
            }
            body += "Line \(line) of filler text about nothing in particular.\n"
            line += 1
        }
        return body + "The closing word is marigold.\n\nReply with only: the secret code, the middle word, then the closing word."
    }

    private static let imageCases: [LabCase] = [
        LabCase(id: "img-color", area: .images, name: "See a color", prompt: "What color is the square in this image? Reply with one word.",
                imageBase64: labImage(square: true), expected: "Red", grade: LabGrade.hasWord("red")),
        LabCase(id: "img-digit", area: .images, name: "Read a number", prompt: "What number is shown in this image? Reply with only the number.",
                imageBase64: labImage(square: false), expected: "7", grade: LabGrade.number(7)),
    ]

    private static let toolCase = LabCase(
        id: "tool-weather", area: .tools, name: "Call a tool",
        prompt: "What's the weather in Paris right now? Use the \(weatherToolName) tool.", usesTool: true,
        expected: "A call to \(weatherToolName) with the city Paris",
        grade: { reply in
            guard let call = reply.toolCalls.first, call.name == weatherToolName else { return false }
            return call.arguments["city"]?.lowercased().contains("paris") == true
        })

    /// A red square, or the digit 7, drawn here so the right answer is known.
    private static func labImage(square: Bool) -> String? {
        let size = 256
        guard let context = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: size, height: size))
        if square {
            context.setFillColor(CGColor(red: 0.9, green: 0.1, blue: 0.1, alpha: 1))
            context.fill(CGRect(x: 48, y: 48, width: 160, height: 160))
        } else {
            let font = CTFontCreateWithName("Helvetica-Bold" as CFString, 200, nil)
            let text = NSAttributedString(string: "7", attributes: [
                NSAttributedString.Key(kCTFontAttributeName as String): font,
                NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(red: 0, green: 0, blue: 0, alpha: 1),
            ])
            context.textPosition = CGPoint(x: 72, y: 56)
            CTLineDraw(CTLineCreateWithAttributedString(text), context)
        }
        guard let image = context.makeImage() else { return nil }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, UTType.png.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, nil)
        return CGImageDestinationFinalize(destination) ? (output as Data).base64EncodedString() : nil
    }
}

public struct LabCaseResult: Codable, Sendable, Identifiable, Equatable {
    public let id: String
    public let area: LabArea
    public let name: String
    public let reply: String
    public let passed: Bool
    public var documentTokens: Int?
    /// What was asked and what was expected. Optional so earlier saved runs still open.
    public var prompt: String?
    public var expected: String?

    public init(id: String, area: LabArea, name: String, reply: String, passed: Bool, documentTokens: Int? = nil,
                prompt: String? = nil, expected: String? = nil) {
        self.prompt = prompt
        self.expected = expected
        self.id = id
        self.area = area
        self.name = name
        self.reply = reply
        self.passed = passed
        self.documentTokens = documentTokens
    }
}

/// A finished run, and what it says the model is good for.
public struct LabReport: Codable, Sendable, Equatable {
    public let modelName: String
    public let date: Date
    public let tokensPerSecond: Double
    public let loadSeconds: Double
    public let memoryBytes: Int64
    public let swapGrowthBytes: Int64
    public let totalMemoryBytes: Int64
    public let supportsImages: Bool
    public let supportsTools: Bool
    /// Nil in reports saved before audio was tested.
    public var supportsAudio: Bool?
    public let results: [LabCaseResult]

    public init(modelName: String, date: Date, tokensPerSecond: Double, loadSeconds: Double, memoryBytes: Int64,
                swapGrowthBytes: Int64, totalMemoryBytes: Int64, supportsImages: Bool, supportsTools: Bool, results: [LabCaseResult], supportsAudio: Bool? = nil) {
        self.supportsAudio = supportsAudio
        self.modelName = modelName
        self.date = date
        self.tokensPerSecond = tokensPerSecond
        self.loadSeconds = loadSeconds
        self.memoryBytes = memoryBytes
        self.swapGrowthBytes = swapGrowthBytes
        self.totalMemoryBytes = totalMemoryBytes
        self.supportsImages = supportsImages
        self.supportsTools = supportsTools
        self.results = results
    }

    public func results(in area: LabArea) -> [LabCaseResult] { results.filter { $0.area == area } }

    public func passed(in area: LabArea) -> Int { results(in: area).filter(\.passed).count }

    public var totalPassed: Int { results.filter(\.passed).count }

    /// How this area went, or nil if it wasn't tested.
    public func rating(in area: LabArea) -> LabRating? {
        if area == .speed {
            guard tokensPerSecond > 0 else { return nil }
            return tokensPerSecond >= 25 ? .strong : tokensPerSecond >= 10 ? .fair : .weak
        }
        return share(area).map(LabRating.init(share:))
    }

    private func share(_ area: LabArea) -> Double? {
        let total = results(in: area).count
        return total == 0 ? nil : Double(passed(in: area)) / Double(total)
    }

    /// The longest document it recalled correctly.
    public var longestDocumentTokens: Int? {
        results(in: .documents).filter(\.passed).compactMap(\.documentTokens).max()
    }

    public var goodFor: [String] {
        var list: [String] = []
        if tokensPerSecond >= 15, (share(.reasoning) ?? 0) >= 0.6 { list.append("Quick questions") }
        if (share(.instructions) ?? 0) >= 0.75 { list.append("Everyday writing") }
        if (share(.code) ?? 0) >= 0.6 { list.append("Coding help") }
        if share(.data) == 1 { list.append("Pulling out structured data") }
        if let longest = longestDocumentTokens {
            list.append(longest >= 20_000 ? "Long documents" : "Short documents")
        }
        if share(.images) == 1 { list.append("Reading images") }
        if let score = share(.audio), score >= 0.8 { list.append("Transcribing audio") }
        if share(.tools) == 1 { list.append("Using tools") }
        return list
    }

    public var limits: [String] {
        var list: [String] = []
        if tokensPerSecond > 0, tokensPerSecond < 10 { list.append("Replies are slow, at \(Int(tokensPerSecond)) tokens per second.") }
        if let score = share(.reasoning), score < 0.6 { list.append("Often gets logic and math wrong.") }
        if let score = share(.code), score < 0.6 { list.append("Unreliable for reading and writing code.") }
        if let score = share(.instructions), score < 0.75 { list.append("Often ignores format and length instructions.") }
        if let score = share(.data), score < 1 { list.append("Doesn't reliably produce valid JSON.") }
        if let lost = results(in: .documents).filter({ !$0.passed }).compactMap(\.documentTokens).min() {
            list.append("Lost track of a \(lost.formatted())-token document.")
        }
        if !supportsImages {
            list.append("Can't read images.")
        } else if let score = share(.images), score < 1 {
            list.append("Misread a test image.")
        }
        if supportsAudio == false {
            list.append("Can't listen to audio.")
        } else if let failed = results(in: .audio).first(where: { !$0.passed }) {
            list.append("Struggled with audio: \(failed.name.lowercased()).")
        }
        if !supportsTools {
            list.append("Can't use tools.")
        } else if let score = share(.tools), score < 1 {
            list.append("Didn't call a tool correctly.")
        }
        if swapGrowthBytes > 1_073_741_824 { list.append("Pushed this Mac into using swap, which slows everything down.") }
        return list
    }
}

/// The best model in each area, from each model's latest report.
public enum LabLeaderboard {
    public struct Winner: Sendable, Equatable {
        public let area: LabArea
        public let modelName: String
        public let passed: Int
        public let total: Int
        public let tokensPerSecond: Double
    }

    /// Highest share of tests passed wins, and the faster model wins a tie. Speed is ranked by speed alone.
    public static func winners(_ reports: [LabReport]) -> [Winner] {
        LabArea.allCases.compactMap { area in
            let entries = reports.compactMap { report -> Winner? in
                if area == .speed {
                    guard report.tokensPerSecond > 0 else { return nil }
                    return Winner(area: area, modelName: report.modelName, passed: 0, total: 0, tokensPerSecond: report.tokensPerSecond)
                }
                let results = report.results(in: area)
                guard !results.isEmpty else { return nil }
                return Winner(area: area, modelName: report.modelName, passed: report.passed(in: area),
                              total: results.count, tokensPerSecond: report.tokensPerSecond)
            }
            return entries.max { a, b in
                let shareA = a.total == 0 ? 0 : Double(a.passed) / Double(a.total)
                let shareB = b.total == 0 ? 0 : Double(b.passed) / Double(b.total)
                return shareA == shareB ? a.tokensPerSecond < b.tokensPerSecond : shareA < shareB
            }
        }
    }
}
