import Foundation
import Testing
@testable import LanternKit

private let full = OllamaModel(name: "m", size: 1, capabilities: ["completion", "vision", "tools", "thinking"], contextLimit: 262_144)
private let basic = OllamaModel(name: "b", size: 1, capabilities: ["completion"])

private let goodAnswers: [String: String] = [
    "speed": "The ocean is wide.", "r-sheep": "9", "r-machines": "3 minutes", "r-multiply": "1,591", "r-sequence": "42", "r-shortest": "Cara",
    "c-sum": "14", "c-reverse": "nre", "c-sort": "2", "c-bug": "3",
    "c-write": "def is_even(n):\n    return n % 2 == 0",
    "i-bullets": "- apple\n- pear\n- plum", "i-short": "A small lantern glows softly.", "i-caps": "GOOD MORNING!", "i-avoid": "Waves roll across a vast blue expanse.",
    "d-object": "```json\n{\"name\": \"Mira\", \"age\": 34}\n```", "d-array": "[\"red\", \"green\", \"blue\"]",
    "doc-2000": "7741 harbor marigold", "doc-8000": "7741, harbor, marigold", "doc-20000": "7741 harbor marigold",
    "img-color": "Red.", "img-digit": "7",
]

private func response(_ text: String) -> LabResponse { LabResponse(text: text, tokensPerSecond: 20) }

@Test("S-040 every test passes a correct answer")
func gradesCorrectAnswers() throws {
    for labCase in ModelLab.cases(for: full) where !labCase.usesTool {
        let answer = try #require(goodAnswers[labCase.id], "no answer for \(labCase.id)")
        #expect(labCase.grade(response(answer)), "\(labCase.id) rejected a correct answer")
    }
}

@Test("S-040 every test fails a wrong answer")
func gradesWrongAnswers() {
    for labCase in ModelLab.cases(for: full) where !labCase.usesTool {
        #expect(!labCase.grade(LabResponse(text: "I am not sure about that one.")), "\(labCase.id) accepted a wrong answer")
    }
}

@Test("S-040 image and tool tests only run for models that can do them")
func filtersByCapability() {
    let ids = Set(ModelLab.cases(for: basic).map(\.id))
    #expect(!ids.contains("img-color"))
    #expect(!ids.contains("tool-weather"))
    #expect(Set(ModelLab.cases(for: full).map(\.id)).isSuperset(of: ["img-color", "img-digit", "tool-weather"]))
}

@Test("S-040 test images are real images")
func makesImages() throws {
    let image = try #require(ModelLab.cases(for: full).first { $0.id == "img-digit" }?.imageBase64)
    let data = try #require(Data(base64Encoded: image))
    #expect(data.starts(with: [0x89, 0x50, 0x4E, 0x47]))
}

@Test("S-040 the longest document only runs if the model can hold it")
func filtersDocuments() {
    #expect(!ModelLab.cases(for: basic).contains { $0.id == "doc-20000" })
    #expect(ModelLab.cases(for: full).contains { $0.id == "doc-20000" })
}

@Test("S-040 a long document carries facts at both ends, at about the right size")
func buildsDocuments() {
    let text = ModelLab.document(tokens: 8_000)
    #expect(text.hasPrefix("The secret code is 7741."))
    #expect(text.contains("The closing word is marigold."))
    let middle = try! #require(text.range(of: "The middle word is harbor."))
    let position = Double(text.distance(from: text.startIndex, to: middle.lowerBound)) / Double(text.count)
    #expect(position > 0.4 && position < 0.6)
    #expect(AttachmentPrompt.estimatedTokens(text) >= 8_000)
}

@Test("S-040 a tool call needs the right tool and argument")
func gradesTools() throws {
    let tool = try #require(ModelLab.cases(for: full).first { $0.usesTool })
    #expect(tool.grade(LabResponse(text: "", toolCalls: [LabToolCall(name: "get_weather", arguments: ["city": "Paris"])])))
    #expect(!tool.grade(LabResponse(text: "It is sunny in Paris.")))
    #expect(!tool.grade(LabResponse(text: "", toolCalls: [LabToolCall(name: "get_weather", arguments: ["city": "Rome"])])))
}

private func report(tps: Double = 28, passed: Bool, swap: Int64 = 0, images: Bool = true, tools: Bool = true, documents: [(Int, Bool)] = [(20_000, true)]) -> LabReport {
    var results = [LabArea.reasoning, .code, .instructions, .data].map {
        LabCaseResult(id: $0.rawValue, area: $0, name: "x", reply: "", passed: passed)
    }
    results += documents.map { LabCaseResult(id: "doc\($0.0)", area: .documents, name: "x", reply: "", passed: $0.1, documentTokens: $0.0) }
    if images { results.append(LabCaseResult(id: "img", area: .images, name: "x", reply: "", passed: passed)) }
    if tools { results.append(LabCaseResult(id: "tool", area: .tools, name: "x", reply: "", passed: passed)) }
    return LabReport(modelName: "m", date: .now, tokensPerSecond: tps, loadSeconds: 1, memoryBytes: 1, swapGrowthBytes: swap,
                     totalMemoryBytes: 1, supportsImages: images, supportsTools: tools, results: results)
}

@Test("S-040 strong scores become Good For")
func goodFor() {
    let list = report(passed: true).goodFor
    #expect(list.contains("Quick questions"))
    #expect(list.contains("Coding help"))
    #expect(list.contains("Long documents"))
    #expect(list.contains("Reading images"))
    #expect(list.contains("Using tools"))
    #expect(report(passed: true).limits.isEmpty)
}

@Test("S-040 weak scores become Limits")
func limits() {
    let list = report(tps: 4, passed: false, swap: 3_000_000_000, documents: [(2_000, true), (8_000, false)]).limits
    #expect(list.contains("Replies are slow, at 4 tokens per second."))
    #expect(list.contains("Often gets logic and math wrong."))
    #expect(list.contains("Lost track of a 8,000-token document."))
    #expect(list.contains("Pushed this Mac into using swap, which slows everything down."))
}

@Test("S-040 what a model can't do is listed plainly")
func missingAbilities() {
    let list = report(passed: true, images: false, tools: false).limits
    #expect(list.contains("Can't read images."))
    #expect(list.contains("Can't use tools."))
}

@Test("S-040 a short document only earns Short documents")
func shortDocuments() {
    #expect(report(passed: true, documents: [(2_000, true), (8_000, true), (20_000, false)]).goodFor.contains("Short documents"))
}

@Test("S-040 tool calls and timing are read from the reply")
func readsLabResponse() throws {
    let json = #"{"message":{"content":"","tool_calls":[{"function":{"name":"get_weather","arguments":{"city":"Paris"}}}]},"eval_count":40,"eval_duration":2000000000,"load_duration":3000000000}"#
    let response = OllamaClient.labResponse(from: Data(json.utf8))
    #expect(response.toolCalls == [LabToolCall(name: "get_weather", arguments: ["city": "Paris"])])
    #expect(response.tokensPerSecond == 20)
    #expect(response.loadSeconds == 3)
}

@Test("S-043 every area explains itself and names its standard, or has none")
func areasExplainThemselves() {
    for area in LabArea.allCases {
        #expect(!area.measures.isEmpty)
        #expect(!area.scoring.isEmpty)
        if area == .images {
            #expect(area.standard == nil)
        } else {
            #expect(area.standard?.relation.isEmpty == false, "\(area) has no standard")
        }
    }
}

@Test("S-043 every test says what it expects")
func casesStateExpectations() {
    for labCase in ModelLab.cases(for: full) {
        #expect(!labCase.expected.isEmpty, "\(labCase.id)")
        #expect(!labCase.shownPrompt.isEmpty, "\(labCase.id)")
    }
}

@Test("S-043 a long document isn't shown in full")
func summarizesDocuments() throws {
    let document = try #require(ModelLab.cases(for: full).first { $0.id == "doc-20000" })
    #expect(document.shownPrompt.count < 200)
    #expect(document.prompt.count > 70_000)
}

@Test("S-043 a document test needs all three facts")
func requiresAllFacts() throws {
    let document = try #require(ModelLab.cases(for: full).first { $0.id == "doc-2000" })
    #expect(document.grade(LabResponse(text: "7741, harbor, marigold")))
    #expect(!document.grade(LabResponse(text: "7741, marigold")))
}

@Test("S-043 ratings follow the score", arguments: [(1.0, LabRating.strong), (0.8, .strong), (0.6, .fair), (0.4, .weak)])
func ratesShares(share: Double, rating: LabRating) {
    #expect(LabRating(share: share) == rating)
}

@Test("S-043 a report saved before these fields existed still opens")
func opensOlderReports() throws {
    let json = #"{"id":"a","area":"code","name":"x","reply":"y","passed":true}"#
    let result = try JSONDecoder().decode(LabCaseResult.self, from: Data(json.utf8))
    #expect(result.prompt == nil)
}
