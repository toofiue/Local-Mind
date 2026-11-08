import Foundation

/// How the sidebar arranges conversations.
public enum ConversationGroups {
    /// Pinned conversations and the rest, each with the most recently updated first.
    public static func split<Item>(_ items: [Item], isPinned: (Item) -> Bool, updatedAt: (Item) -> Date) -> (pinned: [Item], recent: [Item]) {
        let sorted = items.sorted { updatedAt($0) > updatedAt($1) }
        return (sorted.filter(isPinned), sorted.filter { !isPinned($0) })
    }

    /// What to select after removing a row: the one below it, or the one above if it was last.
    public static func next<ID: Equatable>(in ids: [ID], afterRemoving id: ID) -> ID? {
        guard let index = ids.firstIndex(of: id) else { return nil }
        if index + 1 < ids.count { return ids[index + 1] }
        return index > 0 ? ids[index - 1] : nil
    }
}
