import Foundation
import Testing
@testable import LanternKit

private struct Row: Equatable {
    let name: String
    let pinned: Bool
    let age: Double
}

private func split(_ rows: [Row]) -> (pinned: [Row], recent: [Row]) {
    ConversationGroups.split(rows, isPinned: \.pinned, updatedAt: { Date(timeIntervalSince1970: 1_000 - $0.age) })
}

@Test("S-013 pinned conversations sort by most recently updated")
func sortsPinned() {
    let rows = [Row(name: "old", pinned: true, age: 50), Row(name: "new", pinned: true, age: 1), Row(name: "other", pinned: false, age: 0)]
    let groups = split(rows)
    #expect(groups.pinned.map(\.name) == ["new", "old"])
    #expect(groups.recent.map(\.name) == ["other"])
}

@Test("S-014 deleting selects the row below, or above at the end", arguments: [
    ("a", "b" as String?),
    ("b", "c"),
    ("c", "b"),
    ("missing", nil),
])
func selectsNext(removing: String, expected: String?) {
    #expect(ConversationGroups.next(in: ["a", "b", "c"], afterRemoving: removing) == expected)
}

@Test("S-014 deleting the only row selects nothing")
func selectsNothing() {
    #expect(ConversationGroups.next(in: ["a"], afterRemoving: "a") == nil)
}

@Test("S-015 search matches message text and ignores case")
func matchesMessages() {
    #expect(ConversationSearch.snippet(for: "ACTOR", title: "Swift", messages: ["An actor is safe."]) == "An actor is safe.")
}

@Test("S-015 a title match with no text match shows the start of the conversation")
func matchesTitles() {
    #expect(ConversationSearch.snippet(for: "swift", title: "Swift notes", messages: ["Hello there"]) == "Hello there")
}

@Test("S-015 no match returns nil")
func noMatch() {
    #expect(ConversationSearch.snippet(for: "zebra", title: "Swift", messages: ["Hello"]) == nil)
}

@Test("S-015 a blank search matches nothing", arguments: ["", "   \n"])
func blankSearch(query: String) {
    #expect(ConversationSearch.snippet(for: query, title: "Swift", messages: ["Hello"]) == nil)
}

@Test("S-015 snippets cut at word boundaries, mark cuts, and flatten lines")
func excerpts() {
    let long = String(repeating: "early words here ", count: 10) + "the\nneedle sits here " + String(repeating: "late words there ", count: 10)
    let snippet = ConversationSearch.snippet(for: "needle", title: "", messages: [long])
    #expect(snippet?.hasPrefix("…") == true)
    #expect(snippet?.hasSuffix("…") == true)
    #expect(snippet?.contains("the needle sits") == true)
    #expect(snippet?.contains("\n") == false)
}

@Test("S-015 accents don't block a match")
func accents() {
    #expect(ConversationSearch.snippet(for: "cafe", title: "", messages: ["Un café"]) == "Un café")
}

@Test("S-013 unpinned conversations return to their place by date")
func keepsPlace() {
    let rows = [Row(name: "c", pinned: false, age: 30), Row(name: "a", pinned: false, age: 10), Row(name: "b", pinned: false, age: 20)]
    #expect(split(rows).recent.map(\.name) == ["a", "b", "c"])
}
