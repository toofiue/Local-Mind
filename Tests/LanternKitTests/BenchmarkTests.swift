import Foundation
import Testing
@testable import LanternKit

private func rule(_ id: String, _ arguments: [String: IFEvalRule.Value] = [:]) -> IFEvalRule {
    IFEvalRule(id: id, arguments: arguments)
}

private func passes(_ rule: IFEvalRule, _ reply: String) -> Bool { IFEvalChecker.passes(rule, reply: reply) }

@Test("S-044 GSM8K answers and questions are read from the published format")
func readsGSM8K() throws {
    let line = #"{"question":"How many?","answer":"Add them.\n#### 1,200"}"#
    let item = try #require(BenchmarkLoader.items(.gsm8k, from: Data(line.utf8)).first)
    #expect(item.kind == .gsm8k(answer: 1_200))
    #expect(item.prompt.contains("How many?"))
}

@Test("S-044 IFEval rules and their values are read")
func readsIFEval() throws {
    let line = #"{"key":1000,"prompt":"Write.","instruction_id_list":["punctuation:no_comma","length_constraints:number_words"],"kwargs":[{},{"relation":"at least","num_words":300}]}"#
    let item = try #require(BenchmarkLoader.items(.ifeval, from: Data(line.utf8)).first)
    #expect(item.id == "ifeval-1000")
    guard case .ifeval(let rules) = item.kind else { Issue.record("wrong kind"); return }
    #expect(rules.count == 2)
    #expect(rules[1].arguments["num_words"] == .int(300))
}

@Test("S-044 HumanEval tasks are read")
func readsHumanEval() throws {
    let line = #"{"task_id":"HumanEval/0","prompt":"def f(x):\n","entry_point":"f","canonical_solution":"    return x\n","test":"def check(c):\n    assert c(1) == 1\n"}"#
    let item = try #require(BenchmarkLoader.items(.humaneval, from: Data(line.utf8)).first)
    #expect(item.id == "HumanEval/0")
}

@Test("S-044 a file that isn't the exact expected one is rejected")
func rejectsWrongFile() {
    for suite in BenchmarkSuite.allCases {
        #expect(!suite.matches(Data("tampered".utf8)))
    }
}

@Test("S-044 final numbers come from the answer line", arguments: [
    ("First 3 then 4.\nAnswer: 18", 18.0),
    ("Answer: $1,200.00", 1_200.0),
    ("So the result is 42", 42.0),
    ("Answer: -3", -3.0),
])
func readsFinalNumbers(reply: String, expected: Double) {
    #expect(BenchmarkGrader.finalNumber(in: reply) == expected)
}

@Test("S-044 a wrong or missing number fails GSM8K")
func failsGSM8K() {
    #expect(BenchmarkGrader.passesGSM8K(answer: 18, reply: "Answer: 18"))
    #expect(!BenchmarkGrader.passesGSM8K(answer: 18, reply: "Answer: 19"))
    #expect(!BenchmarkGrader.passesGSM8K(answer: 18, reply: "I can't tell."))
}

@Test("S-044 a completion is joined to the function's prompt")
func buildsProgramFromCompletion() {
    let program = BenchmarkGrader.humanEvalProgram(functionPrompt: "def f(x):\n", test: "def check(c): pass", entryPoint: "f", reply: "```python\n    return x\n```")
    #expect(program.hasPrefix("def f(x):\n    return x"))
    #expect(program.hasSuffix("check(f)\n"))
}

@Test("S-044 a repeated function keeps the prompt's imports, not its body")
func buildsProgramFromWholeFunction() {
    let prompt = "from typing import List\n\n\ndef f(x: List[int]):\n    \"\"\"Doc.\"\"\"\n"
    let reply = "```python\ndef f(x: List[int]):\n    return x\n```"
    let program = BenchmarkGrader.humanEvalProgram(functionPrompt: prompt, test: "def check(c): pass", entryPoint: "f", reply: reply)
    #expect(program.contains("from typing import List"))
    #expect(!program.contains("Doc."))
    #expect(program.components(separatedBy: "def f(").count == 2)
}

@Test("S-044 strict scoring needs every rule met")
func scoresStrictly() {
    let rules = [rule("punctuation:no_comma"), rule("startend:quotation")]
    #expect(IFEvalChecker.failedRules(rules, reply: "\"No commas here\"").isEmpty)
    #expect(IFEvalChecker.failedRules(rules, reply: "\"Yes, a comma\"") == ["punctuation:no_comma"])
}

@Test("S-044 keyword rules")
func keywordRules() {
    #expect(passes(rule("keywords:existence", ["keywords": .list(["sea", "sky"])]), "The SEA and the sky"))
    #expect(!passes(rule("keywords:existence", ["keywords": .list(["sea", "sky"])]), "The sea"))
    let frequency = rule("keywords:frequency", ["keyword": .text("ai"), "frequency": .int(2), "relation": .text("at least")])
    #expect(passes(frequency, "AI and ai"))
    #expect(!passes(frequency, "only one ai"))
    let forbidden = rule("keywords:forbidden_words", ["forbidden_words": .list(["cat"])])
    #expect(passes(forbidden, "A catalog of dogs"))
    #expect(!passes(forbidden, "A cat sat"))
    let letters = rule("keywords:letter_frequency", ["letter": .text("z"), "let_frequency": .int(2), "let_relation": .text("less than")])
    #expect(passes(letters, "one z here"))
    #expect(!passes(letters, "zz"))
}

@Test("S-044 length rules")
func lengthRules() {
    let wordsAtLeast = rule("length_constraints:number_words", ["num_words": .int(3), "relation": .text("at least")])
    #expect(passes(wordsAtLeast, "one two three"))
    #expect(!passes(wordsAtLeast, "one two"))
    let sentences = rule("length_constraints:number_sentences", ["num_sentences": .int(3), "relation": .text("less than")])
    #expect(passes(sentences, "One here. Two here."))
    #expect(!passes(sentences, "One here. Two here. Three here. Four here."))
    let paragraphs = rule("length_constraints:number_paragraphs", ["num_paragraphs": .int(2)])
    #expect(passes(paragraphs, "First\n***\nSecond"))
    #expect(!passes(paragraphs, "First\n***\n\n***\nThird"))
    let nth = rule("length_constraints:nth_paragraph_first_word", ["num_paragraphs": .int(2), "nth_paragraph": .int(2), "first_word": .text("second")])
    #expect(passes(nth, "First one.\n\nSecond, indeed."))
    #expect(!passes(nth, "First one.\n\nThird."))
}

@Test("S-044 content and format rules")
func formatRules() {
    #expect(passes(rule("detectable_content:number_placeholders", ["num_placeholders": .int(2)]), "[a] and [b]"))
    #expect(!passes(rule("detectable_content:number_placeholders", ["num_placeholders": .int(2)]), "[a]"))
    #expect(passes(rule("detectable_content:postscript", ["postscript_marker": .text("P.S.")]), "Hi\n\nP.S. bye"))
    #expect(passes(rule("detectable_content:postscript", ["postscript_marker": .text("P.P.S")]), "Hi\n\nP.P.S bye"))
    #expect(!passes(rule("detectable_content:postscript", ["postscript_marker": .text("P.S.")]), "Hi, bye"))
    #expect(passes(rule("detectable_format:number_bullet_lists", ["num_bullets": .int(2)]), "* one\n- two"))
    #expect(!passes(rule("detectable_format:number_bullet_lists", ["num_bullets": .int(2)]), "* one"))
    #expect(passes(rule("detectable_format:constrained_response"), "My answer is yes."))
    #expect(!passes(rule("detectable_format:constrained_response"), "Sure."))
    #expect(passes(rule("detectable_format:number_highlighted_sections", ["num_highlights": .int(2)]), "*one* and **two**"))
    #expect(!passes(rule("detectable_format:number_highlighted_sections", ["num_highlights": .int(2)]), "plain"))
    let sections = rule("detectable_format:multiple_sections", ["section_spliter": .text("SECTION"), "num_sections": .int(2)])
    #expect(passes(sections, "SECTION 1\na\nSECTION 2\nb"))
    #expect(!passes(sections, "SECTION 1\na"))
    #expect(passes(rule("detectable_format:json_format"), "```json\n{\"a\": 1}\n```"))
    #expect(!passes(rule("detectable_format:json_format"), "{a: 1"))
    #expect(passes(rule("detectable_format:title"), "<<Title>>\nBody"))
    #expect(!passes(rule("detectable_format:title"), "<<>>\nBody"))
}

@Test("S-044 combination, start and end, and case rules")
func otherRules() {
    #expect(passes(rule("combination:two_responses"), "First one\n******\nSecond one"))
    #expect(!passes(rule("combination:two_responses"), "Same\n******\nSame"))
    #expect(passes(rule("combination:repeat_prompt", ["prompt_to_repeat": .text("Say hi")]), "say hi\nHello"))
    #expect(!passes(rule("combination:repeat_prompt", ["prompt_to_repeat": .text("Say hi")]), "Hello"))
    #expect(passes(rule("startend:end_checker", ["end_phrase": .text("Is there anything else")]), "Done. Is there anything else\""))
    #expect(!passes(rule("startend:end_checker", ["end_phrase": .text("the end")]), "not yet"))
    #expect(passes(rule("startend:quotation"), "\"quoted\""))
    #expect(!passes(rule("startend:quotation"), "not quoted"))
    let capitals = rule("change_case:capital_word_frequency", ["capital_frequency": .int(2), "capital_relation": .text("at least")])
    #expect(passes(capitals, "VERY LOUD words"))
    #expect(!passes(capitals, "one LOUD word"))
    #expect(passes(rule("change_case:english_capital"), "THIS IS A SENTENCE WRITTEN IN ENGLISH FOR THE TEST"))
    #expect(!passes(rule("change_case:english_capital"), "This is not all capitals"))
    #expect(passes(rule("change_case:english_lowercase"), "this is a sentence written in english for the test"))
    #expect(!passes(rule("change_case:english_lowercase"), "This Has Capitals in english"))
    #expect(passes(rule("punctuation:no_comma"), "no commas"))
    #expect(passes(rule("language:response_language", ["language": .text("ru")]), "Это предложение написано на русском языке для проверки."))
    #expect(!passes(rule("language:response_language", ["language": .text("ru")]), "This sentence is written in English for the test."))
}

@Test("S-044 an unknown rule or an empty reply never passes")
func refusesUnknowns() {
    #expect(!passes(rule("made:up"), "anything"))
    #expect(!passes(rule("punctuation:no_comma"), "   "))
}

private func items(_ count: Int) -> [BenchmarkItem] {
    (0..<count).map { BenchmarkItem(id: "q\($0)", suite: .gsm8k, prompt: "p", kind: .gsm8k(answer: 1)) }
}

@Test("S-044 a sample is the same every time and doesn't depend on order")
func samplesStably() {
    let first = BenchmarkLoader.sample(items(100), count: 10).map(\.id)
    #expect(first == BenchmarkLoader.sample(items(100).reversed(), count: 10).map(\.id))
    #expect(first != (0..<10).map { "q\($0)" })
    #expect(BenchmarkLoader.sample(items(5), count: 10).count == 5)
}

private func result(_ suite: BenchmarkSuite, passed: Int, failed: Int) -> BenchmarkSuiteResult {
    let all = (0..<passed).map { BenchmarkItemResult(id: "p\($0)", passed: true, reply: "") }
        + (0..<failed).map { BenchmarkItemResult(id: "f\($0)", passed: false, reply: "") }
    return BenchmarkSuiteResult(suite: suite, items: all, planned: all.count)
}

@Test("S-044 only a complete set counts as complete")
func recognizesComplete() {
    #expect(!result(.humaneval, passed: 40, failed: 10).isComplete)
    #expect(result(.humaneval, passed: 100, failed: 64).isComplete)
    #expect(result(.humaneval, passed: 100, failed: 64).marginOfError == 0)
}

@Test("S-044 a bigger sample has a smaller margin of error")
func narrowsMargin() {
    let small = result(.gsm8k, passed: 40, failed: 10).marginOfError
    let large = result(.gsm8k, passed: 160, failed: 40).marginOfError
    #expect(small > large)
    #expect(small > 0.08 && small < 0.14)
}

@Test("S-044 the estimate grows with size and shrinks with speed")
func estimatesTime() {
    let sample = BenchmarkEstimate.minutes(size: .sample50, suites: [.gsm8k], tokensPerSecond: 25)
    #expect(sample >= 5 && sample <= 7)
    #expect(BenchmarkEstimate.minutes(size: .complete, suites: [.gsm8k], tokensPerSecond: 25) > sample)
    #expect(BenchmarkEstimate.minutes(size: .sample50, suites: [.gsm8k], tokensPerSecond: 50) < sample)
}
