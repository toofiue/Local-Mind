import Foundation

/// Finds conversations by their title or message text.
public enum ConversationSearch {
    private static let options: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]

    /// The snippet to show if the conversation matches, or nil if it doesn't.
    /// `messages` should be in conversation order.
    public static func snippet(for query: String, title: String, messages: [String]) -> String? {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return nil }
        for message in messages {
            if let range = message.range(of: needle, options: options) {
                return excerpt(of: message, around: range)
            }
        }
        guard title.range(of: needle, options: options) != nil else { return nil }
        guard let first = messages.first else { return "" }
        return excerpt(of: first, around: first.startIndex..<first.startIndex)
    }

    /// About 30 characters before the match and 50 after, cut at word boundaries.
    private static func excerpt(of text: String, around range: Range<String.Index>) -> String {
        var start = text.index(range.lowerBound, offsetBy: -30, limitedBy: text.startIndex) ?? text.startIndex
        var end = text.index(range.upperBound, offsetBy: 50, limitedBy: text.endIndex) ?? text.endIndex
        if start != text.startIndex, let space = text[start..<range.lowerBound].firstIndex(where: \.isWhitespace) {
            start = text.index(after: space)
        }
        if end != text.endIndex, let space = text[range.upperBound..<end].lastIndex(where: \.isWhitespace) {
            end = space
        }
        let body = text[start..<end].split(whereSeparator: \.isWhitespace).joined(separator: " ")
        return (start == text.startIndex ? "" : "…") + body + (end == text.endIndex ? "" : "…")
    }
}

/// How the sidebar arranges conversations.
public enum ConversationGroups {
    /// Pinned conversations and the rest, each with the most recently updated first.
    public static func split<Item>(_ items: [Item], isPinned: (Item) -> Bool, updatedAt: (Item) -> Date) -> (pinned: [Item], recent: [Item]) {
        let sorted = items.sorted { updatedAt($0) > updatedAt($1) }
        return (sorted.filter(isPinned), sorted.filter { !isPinned($0) })
    }

    /// Splits conversations, newest first, into Today, Yesterday, Previous 7 Days, Previous 30 Days,
    /// and Older, the way the sidebar shows them. Empty groups are left out; order is kept.
    public static func byDate<Item>(_ items: [Item], updatedAt: (Item) -> Date,
                                    now: Date = .now, calendar: Calendar = .current) -> [(title: String, items: [Item])] {
        let today = calendar.startOfDay(for: now)
        func title(_ date: Date) -> String {
            let day = calendar.startOfDay(for: date)
            let days = calendar.dateComponents([.day], from: day, to: today).day ?? 0
            switch days {
            case ..<1: return "Today"
            case 1: return "Yesterday"
            case 2..<8: return "Previous 7 Days"
            case 8..<31: return "Previous 30 Days"
            default: return "Older"
            }
        }
        var groups: [(title: String, items: [Item])] = []
        for item in items.sorted(by: { updatedAt($0) > updatedAt($1) }) {
            let name = title(updatedAt(item))
            if groups.last?.title == name { groups[groups.count - 1].items.append(item) } else { groups.append((name, [item])) }
        }
        return groups
    }

    /// What to select after removing a row: the one below it, or the one above if it was last.
    public static func next<ID: Equatable>(in ids: [ID], afterRemoving id: ID) -> ID? {
        guard let index = ids.firstIndex(of: id) else { return nil }
        if index + 1 < ids.count { return ids[index + 1] }
        return index > 0 ? ids[index - 1] : nil
    }
}
