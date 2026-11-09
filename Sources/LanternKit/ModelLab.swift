import CoreGraphics
import CoreText
import Foundation
import ImageIO
import UniformTypeIdentifiers

public enum LabArea: String, Codable, CaseIterable, Sendable, Identifiable {
    case speed, reasoning, code, instructions, data, documents, images, tools

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
        case .tools: "Using Tools"
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
    public let grade: @Sendable (LabResponse) -> Bool
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
    public static func cases(for model: OllamaModel) -> [LabCase] {
        var cases = baseCases
        var sizes = [2_000, 8_000]
        if model.contextLimit >= 20_000 { sizes.append(20_000) }
        cases += sizes.map(documentCase)
        if model.supportsImages { cases += imageCases }
        if model.capabilities.contains("tools") { cases.append(toolCase) }
        return cases
    }

    private static let baseCases: [LabCase] = [
        LabCase(id: "speed", area: .speed, name: "Write a paragraph", prompt: "Write one short paragraph about the ocean.",
                grade: { !$0.text.isEmpty && $0.tokensPerSecond > 0 }),

        LabCase(id: "r-sheep", area: .reasoning, name: "Trick question",
                prompt: "A farmer has 17 sheep. All but 9 run away. How many sheep are left? Reply with only the number.",
                grade: LabGrade.number(9)),
        LabCase(id: "r-machines", area: .reasoning, name: "Rates",
                prompt: "If 3 machines make 3 widgets in 3 minutes, how many minutes do 100 machines take to make 100 widgets? Reply with only the number.",
                grade: LabGrade.number(3)),
        LabCase(id: "r-multiply", area: .reasoning, name: "Arithmetic",
                prompt: "What is 37 times 43? Reply with only the number.", grade: LabGrade.number(1_591)),
        LabCase(id: "r-sequence", area: .reasoning, name: "Number pattern",
                prompt: "What number comes next: 2, 6, 12, 20, 30? Reply with only the number.", grade: LabGrade.number(42)),
        LabCase(id: "r-shortest", area: .reasoning, name: "Logic",
                prompt: "Anna is taller than Ben. Ben is taller than Cara. Who is the shortest? Reply with only the name.",
                grade: LabGrade.hasWord("cara")),

        LabCase(id: "c-sum", area: .code, name: "Read Python",
                prompt: "What does this Python print? Reply with only the output.\n\nprint(sum(i * i for i in range(4)))",
                grade: LabGrade.number(14)),
        LabCase(id: "c-reverse", area: .code, name: "Read string slicing",
                prompt: "What does this Python print? Reply with only the output.\n\nprint(\"lantern\"[::-1][:3])",
                grade: LabGrade.hasWord("nre")),
        LabCase(id: "c-sort", area: .code, name: "Read Swift",
                prompt: "What does this Swift print? Reply with only the output.\n\nprint([3, 1, 2].sorted()[1])",
                grade: LabGrade.number(2)),
        LabCase(id: "c-bug", area: .code, name: "Find a bug",
                prompt: "This code should print the sum of the list. Which line number has the bug? Reply with only the number.\n\n1: total = 0\n2: for n in [1, 2, 3]:\n3:     total = n\n4: print(total)",
                grade: LabGrade.number(3)),
        LabCase(id: "c-write", area: .code, name: "Write a function",
                prompt: "Write a Python function named is_even that returns True when n is even. Reply with only the code.",
                grade: { reply in
                    let compact = reply.text.replacingOccurrences(of: " ", with: "")
                    return compact.contains("defis_even") && (compact.contains("%2") || compact.contains("&1"))
                }),

        LabCase(id: "i-bullets", area: .instructions, name: "Exact format",
                prompt: "List three fruits as exactly three lines, each starting with \"- \". Write nothing else.",
                grade: { reply in
                    let lines = reply.text.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
                    return lines.count == 3 && lines.allSatisfy { $0.hasPrefix("- ") }
                }),
        LabCase(id: "i-short", area: .instructions, name: "Length limit",
                prompt: "Describe a lantern in fewer than 12 words. Use the word lantern.",
                grade: { reply in
                    let words = LabGrade.words(reply.text)
                    return words.count < 12 && words.contains("lantern")
                }),
        LabCase(id: "i-caps", area: .instructions, name: "Capitals only",
                prompt: "Say good morning in all capital letters.",
                grade: { reply in
                    let letters = reply.text.filter(\.isLetter)
                    return !letters.isEmpty && letters == letters.uppercased()
                }),
        LabCase(id: "i-avoid", area: .instructions, name: "Avoid a word",
                prompt: "Describe the sea in one sentence without using the word \"the\".",
                grade: { reply in
                    let words = LabGrade.words(reply.text)
                    let onTopic = !Set(words).isDisjoint(with: ["sea", "ocean", "water", "waters", "waves", "wave", "tide", "tides", "blue", "salt"])
                    return words.count > 2 && !words.contains("the") && onTopic
                }),

        LabCase(id: "d-object", area: .data, name: "Extract to JSON",
                prompt: "Turn this into a JSON object with the keys name and age. Reply with only the JSON.\n\nMira is 34 years old.",
                grade: { reply in
                    guard let object = LabGrade.json(reply.text) as? [String: Any] else { return false }
                    return (object["name"] as? String)?.lowercased().contains("mira") == true && (object["age"] as? Int) == 34
                }),
        LabCase(id: "d-array", area: .data, name: "JSON list",
                prompt: "Reply with only a JSON array of the three primary colors of light, in lowercase.",
                grade: { reply in
                    guard let list = LabGrade.json(reply.text) as? [String] else { return false }
                    return Set(list) == ["red", "green", "blue"]
                }),
    ]

    private static func documentCase(tokens: Int) -> LabCase {
        LabCase(id: "doc-\(tokens)", area: .documents, name: "\(tokens.formatted()) tokens",
                prompt: document(tokens: tokens), documentTokens: tokens,
                grade: { reply in
                    let words = LabGrade.words(reply.text)
                    return words.contains("7741") && words.contains("marigold")
                })
    }

    /// A long document with one fact at the very start and one at the very end.
    static func document(tokens: Int) -> String {
        var body = "The secret code is 7741.\n"
        var line = 1
        while body.count < tokens * 4 {
            body += "Line \(line) of filler text about nothing in particular.\n"
            line += 1
        }
        return body + "The closing word is marigold.\n\nReply with only: the secret code, then the closing word."
    }

    private static let imageCases: [LabCase] = [
        LabCase(id: "img-color", area: .images, name: "See a color", prompt: "What color is the square in this image? Reply with one word.",
                imageBase64: labImage(square: true), grade: LabGrade.hasWord("red")),
        LabCase(id: "img-digit", area: .images, name: "Read a number", prompt: "What number is shown in this image? Reply with only the number.",
                imageBase64: labImage(square: false), grade: LabGrade.number(7)),
    ]

    private static let toolCase = LabCase(
        id: "tool-weather", area: .tools, name: "Call a tool",
        prompt: "What's the weather in Paris right now? Use the \(weatherToolName) tool.", usesTool: true,
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

    public init(id: String, area: LabArea, name: String, reply: String, passed: Bool, documentTokens: Int? = nil) {
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
    public let results: [LabCaseResult]

    public init(modelName: String, date: Date, tokensPerSecond: Double, loadSeconds: Double, memoryBytes: Int64,
                swapGrowthBytes: Int64, totalMemoryBytes: Int64, supportsImages: Bool, supportsTools: Bool, results: [LabCaseResult]) {
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
        if !supportsTools {
            list.append("Can't use tools.")
        } else if let score = share(.tools), score < 1 {
            list.append("Didn't call a tool correctly.")
        }
        if swapGrowthBytes > 1_073_741_824 { list.append("Pushed this Mac into using swap, which slows everything down.") }
        return list
    }
}
