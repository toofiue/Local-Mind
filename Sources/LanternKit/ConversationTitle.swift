import Foundation

public enum ConversationTitle {
    public static let placeholder = "New Conversation"

    /// The first line of the first message, cut to 50 characters at a word boundary.
    public static func make(from message: String, limit: Int = 50) -> String {
        let firstLine = message.split(whereSeparator: \.isNewline)
            .first { !$0.allSatisfy(\.isWhitespace) } ?? ""
        let words = firstLine.split(whereSeparator: \.isWhitespace)
        guard let first = words.first else { return placeholder }
        var title = String(first.prefix(limit))
        for word in words.dropFirst() {
            guard title.count + 1 + word.count <= limit else { break }
            title += " " + word
        }
        return title
    }
}
