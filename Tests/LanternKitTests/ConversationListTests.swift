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

@Test("S-013 unpinned conversations return to their place by date")
func keepsPlace() {
    let rows = [Row(name: "c", pinned: false, age: 30), Row(name: "a", pinned: false, age: 10), Row(name: "b", pinned: false, age: 20)]
    #expect(split(rows).recent.map(\.name) == ["a", "b", "c"])
}
