import Testing
@testable import LanternKit

@Test("S-007 headings, paragraphs, and rules")
func basics() {
    #expect(Markdown.parse("## Title\n\nSome text\nmore\n\n---") == [
        .heading(level: 2, text: "Title"),
        .paragraph("Some text\nmore"),
        .rule,
    ])
}

@Test("S-007 an unclosed code fence is still code")
func unclosedFence() {
    #expect(Markdown.parse("Look:\n```swift\nlet a = 1") == [
        .paragraph("Look:"),
        .code(language: "swift", code: "let a = 1", isClosed: false),
    ])
}

@Test("S-008 code has no fence markers or language label")
func closedFence() {
    #expect(Markdown.parse("```python\nprint(1)\n\nprint(2)\n```") == [
        .code(language: "python", code: "print(1)\n\nprint(2)", isClosed: true),
    ])
}

@Test("A fence with no language has a nil language")
func plainFence() {
    #expect(Markdown.parse("```\nx\n```") == [.code(language: nil, code: "x", isClosed: true)])
}

@Test("A code block indented inside a list loses that indent")
func indentedFence() {
    #expect(Markdown.parse("   ```js\n   a()\n     b()\n   ```") == [
        .code(language: "js", code: "a()\n  b()", isClosed: true),
    ])
}

@Test("Markdown inside a code block stays literal")
func literalCode() {
    #expect(Markdown.parse("```\n# not a heading\n- not a list\n```") == [
        .code(language: nil, code: "# not a heading\n- not a list", isClosed: true),
    ])
}

@Test("S-007 tables pad short rows")
func tables() {
    #expect(Markdown.parse("| A | B |\n|---|:-:|\n| 1 | 2 |\n| 3 |") == [
        .table(header: ["A", "B"], rows: [["1", "2"], ["3", ""]]),
    ])
}

@Test("A pipe with no separator line is ordinary text")
func notATable() {
    #expect(Markdown.parse("a | b") == [.paragraph("a | b")])
}

@Test("S-007 lists keep order, nesting, and continuation lines")
func lists() {
    #expect(Markdown.parse("1. One\n   more\n2. Two\n  - Sub") == [
        .list([
            MarkdownListItem(level: 0, marker: "1.", text: "One more"),
            MarkdownListItem(level: 0, marker: "2.", text: "Two"),
            MarkdownListItem(level: 1, marker: nil, text: "Sub"),
        ]),
    ])
}

@Test("A blank line between items keeps one list")
func looseList() {
    let blocks = Markdown.parse("- a\n\n- b\n\nAfter")
    #expect(blocks == [
        .list([MarkdownListItem(level: 0, marker: nil, text: "a"), MarkdownListItem(level: 0, marker: nil, text: "b")]),
        .paragraph("After"),
    ])
}

@Test("Quotes join their lines")
func quotes() {
    #expect(Markdown.parse("> a\n> b") == [.quote("a\nb")])
}

@Test("Empty text has no blocks")
func empty() {
    #expect(Markdown.parse("").isEmpty)
}
