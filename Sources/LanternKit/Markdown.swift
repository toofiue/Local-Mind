import Foundation

public struct MarkdownListItem: Sendable, Equatable {
    public let level: Int
    /// The number as written ("1."), or nil for a bullet.
    public let marker: String?
    public var text: String

    public init(level: Int, marker: String?, text: String) {
        self.level = level
        self.marker = marker
        self.text = text
    }
}

public enum MarkdownBlock: Sendable, Equatable {
    case heading(level: Int, text: String)
    case paragraph(String)
    case list([MarkdownListItem])
    case table(header: [String], rows: [[String]])
    case code(language: String?, code: String, isClosed: Bool)
    case quote(String)
    case rule
}

/// Splits model output into blocks. Text may still be streaming, so an
/// unfinished code block is still a code block.
public enum Markdown {
    public static func parse(_ source: String) -> [MarkdownBlock] {
        let lines = source.replacingOccurrences(of: "\r\n", with: "\n")
            .split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var blocks: [MarkdownBlock] = []
        var paragraph: [String] = []
        var index = 0

        func flushParagraph() {
            guard !paragraph.isEmpty else { return }
            blocks.append(.paragraph(paragraph.joined(separator: "\n")))
            paragraph = []
        }

        while index < lines.count {
            let line = lines[index]
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if let fence = Fence(trimmed) {
                flushParagraph()
                let indent = line.prefix(while: \.isWhitespace).count
                index += 1
                var code: [String] = []
                var isClosed = false
                while index < lines.count {
                    if fence.closes(lines[index].trimmingCharacters(in: .whitespaces)) {
                        isClosed = true
                        index += 1
                        break
                    }
                    code.append(removingIndent(lines[index], upTo: indent))
                    index += 1
                }
                blocks.append(.code(language: fence.language, code: code.joined(separator: "\n"), isClosed: isClosed))
            } else if trimmed.isEmpty {
                flushParagraph()
                index += 1
            } else if let heading = heading(trimmed) {
                flushParagraph()
                blocks.append(.heading(level: heading.level, text: heading.text))
                index += 1
            } else if isRule(trimmed) {
                flushParagraph()
                blocks.append(.rule)
                index += 1
            } else if trimmed.contains("|"), index + 1 < lines.count, isTableSeparator(lines[index + 1]) {
                flushParagraph()
                let header = cells(trimmed)
                index += 2
                var rows: [[String]] = []
                while index < lines.count {
                    let row = lines[index].trimmingCharacters(in: .whitespaces)
                    guard !row.isEmpty, row.contains("|") else { break }
                    var values = cells(row)
                    while values.count < header.count { values.append("") }
                    rows.append(Array(values.prefix(header.count)))
                    index += 1
                }
                blocks.append(.table(header: header, rows: rows))
            } else if trimmed.hasPrefix(">") {
                flushParagraph()
                var quoted: [String] = []
                while index < lines.count {
                    let row = lines[index].trimmingCharacters(in: .whitespaces)
                    guard row.hasPrefix(">") else { break }
                    quoted.append(String(row.dropFirst()).trimmingCharacters(in: .whitespaces))
                    index += 1
                }
                blocks.append(.quote(quoted.joined(separator: "\n")))
            } else if listItem(line) != nil {
                flushParagraph()
                var items: [MarkdownListItem] = []
                while index < lines.count {
                    if let item = listItem(lines[index]) {
                        items.append(item)
                        index += 1
                        continue
                    }
                    let row = lines[index].trimmingCharacters(in: .whitespaces)
                    if row.isEmpty {
                        // A blank line only ends the list if no item follows it.
                        var next = index + 1
                        while next < lines.count, lines[next].trimmingCharacters(in: .whitespaces).isEmpty { next += 1 }
                        guard next < lines.count, listItem(lines[next]) != nil else { break }
                        index = next
                        continue
                    }
                    guard lines[index].first?.isWhitespace == true, Fence(row) == nil else { break }
                    items[items.count - 1].text += " " + row
                    index += 1
                }
                blocks.append(.list(items))
            } else {
                paragraph.append(trimmed)
                index += 1
            }
        }
        flushParagraph()
        return blocks
    }

    private struct Fence: Equatable {
        let character: Character
        let length: Int
        let language: String?

        init?(_ trimmed: String) {
            guard let first = trimmed.first, first == "`" || first == "~" else { return nil }
            let run = trimmed.prefix(while: { $0 == first }).count
            guard run >= 3 else { return nil }
            character = first
            length = run
            let info = trimmed.dropFirst(run).trimmingCharacters(in: .whitespaces)
            language = info.isEmpty ? nil : info.split(separator: " ").first.map(String.init)
        }

        func closes(_ trimmed: String) -> Bool {
            trimmed.count >= length && trimmed.allSatisfy { $0 == character }
        }
    }

    private static func removingIndent(_ line: String, upTo indent: Int) -> String {
        String(line.dropFirst(min(indent, line.prefix(while: \.isWhitespace).count)))
    }

    private static func heading(_ trimmed: String) -> (level: Int, text: String)? {
        let level = trimmed.prefix(while: { $0 == "#" }).count
        guard (1...6).contains(level), trimmed.dropFirst(level).first == " " else { return nil }
        var text = trimmed.dropFirst(level).trimmingCharacters(in: .whitespaces)
        while text.hasSuffix("#") { text.removeLast() }
        return (level, text.trimmingCharacters(in: .whitespaces))
    }

    private static func isRule(_ trimmed: String) -> Bool {
        let marks = trimmed.filter { !$0.isWhitespace }
        guard marks.count >= 3, let first = marks.first, "-*_".contains(first) else { return false }
        return marks.allSatisfy { $0 == first }
    }

    private static func isTableSeparator(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.contains("-"), trimmed.contains("|") else { return false }
        return cells(trimmed).allSatisfy { cell in
            !cell.isEmpty && cell.contains("-") && cell.allSatisfy { $0 == "-" || $0 == ":" }
        }
    }

    private static func cells(_ row: String) -> [String] {
        var body = Substring(row)
        if body.hasPrefix("|") { body = body.dropFirst() }
        if body.hasSuffix("|") { body = body.dropLast() }
        var result: [String] = []
        var current = ""
        var escaped = false
        for character in body {
            if escaped {
                current.append(character)
                escaped = false
            } else if character == "\\" {
                escaped = true
            } else if character == "|" {
                result.append(current.trimmingCharacters(in: .whitespaces))
                current = ""
            } else {
                current.append(character)
            }
        }
        result.append(current.trimmingCharacters(in: .whitespaces))
        return result
    }

    private static func listItem(_ line: String) -> MarkdownListItem? {
        let indent = line.prefix(while: \.isWhitespace).reduce(0) { $0 + ($1 == "\t" ? 2 : 1) }
        let body = line.drop(while: \.isWhitespace)
        let level = min(indent / 2, 4)
        if let first = body.first, "-*+".contains(first), body.dropFirst().first == " " {
            let text = body.dropFirst(2).trimmingCharacters(in: .whitespaces)
            return MarkdownListItem(level: level, marker: nil, text: text)
        }
        let digits = body.prefix(while: \.isNumber)
        let rest = body.dropFirst(digits.count)
        if !digits.isEmpty, let mark = rest.first, ".)".contains(mark), rest.dropFirst().first == " " {
            let text = rest.dropFirst(2).trimmingCharacters(in: .whitespaces)
            return MarkdownListItem(level: level, marker: digits + ".", text: text)
        }
        return nil
    }
}
