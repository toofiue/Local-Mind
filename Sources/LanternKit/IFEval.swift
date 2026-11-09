import Foundation
import NaturalLanguage

/// One instruction from IFEval, with the values it was given.
public struct IFEvalRule: Sendable, Equatable {
    public enum Value: Sendable, Equatable {
        case int(Int), text(String), list([String])

        init?(_ raw: Any) {
            if let number = raw as? Int {
                self = .int(number)
            } else if let string = raw as? String {
                self = .text(string)
            } else if let strings = raw as? [String] {
                self = .list(strings)
            } else {
                return nil
            }
        }
    }

    public let id: String
    public let arguments: [String: Value]

    public init(id: String, arguments: [String: Value] = [:]) {
        self.id = id
        self.arguments = arguments
    }

    fileprivate func int(_ key: String) -> Int? {
        if case .int(let value)? = arguments[key] { return value }
        return nil
    }

    fileprivate func text(_ key: String) -> String? {
        if case .text(let value)? = arguments[key] { return value }
        return nil
    }

    fileprivate func list(_ key: String) -> [String] {
        if case .list(let value)? = arguments[key] { return value }
        return []
    }
}

/// Lantern's port of IFEval's published checkers, one for each of its 25 instruction types.
public enum IFEvalChecker {
    /// Strict scoring: a reply passes only if it meets every rule.
    public static func failedRules(_ rules: [IFEvalRule], reply: String) -> [String] {
        rules.filter { !passes($0, reply: reply) }.map(\.id)
    }

    static func passes(_ rule: IFEvalRule, reply: String) -> Bool {
        let trimmed = reply.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        switch rule.id {
        case "keywords:existence":
            return rule.list("keywords").allSatisfy { matches(NSRegularExpression.escapedPattern(for: $0), in: reply, caseless: true) > 0 }
        case "keywords:frequency":
            guard let keyword = rule.text("keyword"), let target = rule.int("frequency") else { return false }
            return compare(matches(NSRegularExpression.escapedPattern(for: keyword), in: reply, caseless: true), rule.text("relation"), target)
        case "keywords:forbidden_words":
            return rule.list("forbidden_words").allSatisfy {
                matches("\\b" + NSRegularExpression.escapedPattern(for: $0) + "\\b", in: reply, caseless: true) == 0
            }
        case "keywords:letter_frequency":
            guard let letter = rule.text("letter")?.lowercased().first, let target = rule.int("let_frequency") else { return false }
            return compare(reply.lowercased().filter { $0 == letter }.count, rule.text("let_relation"), target)
        case "language:response_language":
            return language(of: reply) == rule.text("language")
        case "length_constraints:number_sentences":
            guard let target = rule.int("num_sentences") else { return false }
            return compare(sentenceCount(reply), rule.text("relation"), target)
        case "length_constraints:number_paragraphs":
            guard let target = rule.int("num_paragraphs") else { return false }
            return dividerParagraphs(reply) == target
        case "length_constraints:number_words":
            guard let target = rule.int("num_words") else { return false }
            return compare(words(reply).count, rule.text("relation"), target)
        case "length_constraints:nth_paragraph_first_word":
            return nthParagraphFirstWord(rule, reply: reply)
        case "detectable_content:number_placeholders":
            guard let target = rule.int("num_placeholders") else { return false }
            return matches(#"\[.*?\]"#, in: reply) >= target
        case "detectable_content:postscript":
            return hasPostscript(marker: rule.text("postscript_marker") ?? "P.S.", reply: reply)
        case "detectable_format:number_bullet_lists":
            guard let target = rule.int("num_bullets") else { return false }
            return matches(#"^\s*\*[^\*].*$"#, in: reply, multiline: true) + matches(#"^\s*-.*$"#, in: reply, multiline: true) == target
        case "detectable_format:constrained_response":
            return ["My answer is yes.", "My answer is no.", "My answer is maybe."].contains { reply.contains($0) }
        case "detectable_format:number_highlighted_sections":
            guard let target = rule.int("num_highlights") else { return false }
            return highlightCount(reply) >= target
        case "detectable_format:multiple_sections":
            guard let splitter = rule.text("section_spliter"), let target = rule.int("num_sections") else { return false }
            return matches("\\s?" + NSRegularExpression.escapedPattern(for: splitter) + "\\s?\\d+\\s?", in: reply) >= target
        case "detectable_format:json_format":
            return isJSON(trimmed)
        case "detectable_format:title":
            return titles(in: reply)
        case "combination:two_responses":
            return twoResponses(reply)
        case "combination:repeat_prompt":
            guard let prompt = rule.text("prompt_to_repeat") else { return false }
            return trimmed.lowercased().hasPrefix(prompt.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())
        case "startend:end_checker":
            guard let phrase = rule.text("end_phrase") else { return false }
            let ending = trimmed.trimmingCharacters(in: CharacterSet(charactersIn: "\"")).lowercased()
            return ending.hasSuffix(phrase.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())
        case "startend:quotation":
            return trimmed.count > 1 && trimmed.hasPrefix("\"") && trimmed.hasSuffix("\"")
        case "change_case:capital_word_frequency":
            guard let target = rule.int("capital_frequency") else { return false }
            return compare(words(reply).filter(isAllCapitals).count, rule.text("capital_relation"), target)
        case "change_case:english_capital":
            return isAllCapitals(reply) && language(of: reply) == "en"
        case "change_case:english_lowercase":
            return reply == reply.lowercased() && reply != reply.uppercased() && language(of: reply) == "en"
        case "punctuation:no_comma":
            return !reply.contains(",")
        default:
            return false
        }
    }

    private static func compare(_ count: Int, _ relation: String?, _ target: Int) -> Bool {
        relation == "less than" ? count < target : count >= target
    }

    private static func matches(_ pattern: String, in text: String, caseless: Bool = false, multiline: Bool = false) -> Int {
        var options: NSRegularExpression.Options = []
        if caseless { options.insert(.caseInsensitive) }
        if multiline { options.insert(.anchorsMatchLines) }
        guard let expression = try? NSRegularExpression(pattern: pattern, options: options) else { return 0 }
        return expression.numberOfMatches(in: text, range: NSRange(text.startIndex..., in: text))
    }

    private static func words(_ text: String) -> [String] {
        guard let expression = try? NSRegularExpression(pattern: #"\w+"#) else { return [] }
        return expression.matches(in: text, range: NSRange(text.startIndex..., in: text))
            .compactMap { Range($0.range, in: text).map { String(text[$0]) } }
    }

    private static func sentenceCount(_ text: String) -> Int {
        let tokenizer = NLTokenizer(unit: .sentence)
        tokenizer.string = text
        return tokenizer.tokens(for: text.startIndex..<text.endIndex).count
    }

    private static func language(of text: String) -> String? {
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        return recognizer.dominantLanguage?.rawValue
    }

    private static func isAllCapitals(_ text: String) -> Bool {
        text == text.uppercased() && text != text.lowercased()
    }

    /// Paragraphs divided by a line of ***. Only the very first or last may be empty.
    private static func dividerParagraphs(_ reply: String) -> Int {
        guard let divider = try? NSRegularExpression(pattern: #"\s?\*\*\*\s?"#) else { return 0 }
        let marked = divider.stringByReplacingMatches(in: reply, range: NSRange(reply.startIndex..., in: reply), withTemplate: "\u{1}")
        let pieces = marked.split(separator: "\u{1}", omittingEmptySubsequences: false)
        var count = pieces.count
        for (index, piece) in pieces.enumerated() where piece.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            guard index == 0 || index == pieces.count - 1 else { return 0 }
            count -= 1
        }
        return count
    }

    private static func nthParagraphFirstWord(_ rule: IFEvalRule, reply: String) -> Bool {
        guard let total = rule.int("num_paragraphs"), let position = rule.int("nth_paragraph"),
              let expected = rule.text("first_word"), position >= 1, position <= total,
              let divider = try? NSRegularExpression(pattern: #"\n\n"#) else { return false }
        let marked = divider.stringByReplacingMatches(in: reply, range: NSRange(reply.startIndex..., in: reply), withTemplate: "\u{1}")
        let paragraphs = marked.split(separator: "\u{1}").filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        guard paragraphs.count == total else { return false }
        let first = paragraphs[position - 1].split(whereSeparator: \.isWhitespace).first ?? ""
        return first.lowercased().trimmingCharacters(in: .punctuationCharacters) == expected.lowercased()
    }

    private static func hasPostscript(marker: String, reply: String) -> Bool {
        let lower = reply.lowercased()
        let pattern: String
        switch marker {
        case "P.P.S": pattern = #"\s*p\.\s?p\.\s?s.*$"#
        case "P.S.": pattern = #"\s*p\.\s?s\..*$"#
        default: pattern = #"\s*"# + NSRegularExpression.escapedPattern(for: marker.lowercased()) + #".*$"#
        }
        return matches(pattern, in: lower, multiline: true) > 0
    }

    private static func highlightCount(_ reply: String) -> Int {
        func nonEmpty(_ pattern: String, trimming: CharacterSet) -> Int {
            guard let expression = try? NSRegularExpression(pattern: pattern) else { return 0 }
            return expression.matches(in: reply, range: NSRange(reply.startIndex..., in: reply)).filter { match in
                guard let range = Range(match.range, in: reply) else { return false }
                return !reply[range].trimmingCharacters(in: trimming).isEmpty
            }.count
        }
        let stars = CharacterSet(charactersIn: "*")
        return nonEmpty(#"\*[^\n\*]*\*"#, trimming: stars) + nonEmpty(#"\*\*[^\n\*]*\*\*"#, trimming: stars)
    }

    private static func isJSON(_ trimmed: String) -> Bool {
        var body = trimmed
        for prefix in ["```json", "```Json", "```JSON", "```"] where body.hasPrefix(prefix) {
            body.removeFirst(prefix.count)
            break
        }
        if body.hasSuffix("```") { body.removeLast(3) }
        return (try? JSONSerialization.jsonObject(with: Data(body.utf8), options: .fragmentsAllowed)) != nil
    }

    private static func titles(in reply: String) -> Bool {
        guard let expression = try? NSRegularExpression(pattern: #"<<[^\n]+>>"#) else { return false }
        return expression.matches(in: reply, range: NSRange(reply.startIndex..., in: reply)).contains { match in
            guard let range = Range(match.range, in: reply) else { return false }
            return !reply[range].trimmingCharacters(in: CharacterSet(charactersIn: "<>")).trimmingCharacters(in: .whitespaces).isEmpty
        }
    }

    private static func twoResponses(_ reply: String) -> Bool {
        let parts = reply.components(separatedBy: "******")
        var valid: [String] = []
        for (index, part) in parts.enumerated() {
            let trimmed = part.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                guard index == 0 || index == parts.count - 1 else { return false }
            } else {
                valid.append(trimmed)
            }
        }
        return valid.count == 2 && valid[0] != valid[1]
    }
}
