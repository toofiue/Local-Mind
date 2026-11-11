import Foundation

/// Spoken clips for testing how well a model hears, with the exact words spoken.
/// Lantern has macOS read them aloud, so the right transcript is known.
public enum LabAudio {
    public struct Clip: Sendable, Identifiable {
        public let id: String
        public let name: String
        /// A macOS voice, or nil for the system voice.
        public let voice: String?
        public let script: String
        /// For a question about the clip: what to ask and the one word that answers it.
        public var question: (prompt: String, answer: String)?

        public var isTranscript: Bool { question == nil }
    }

    /// Original paragraphs with no numbers, so how a model writes numbers can't count against it.
    static let paragraphs = [
        "On the edge of the old town there is a small market where farmers sell bread, honey, and fresh vegetables every morning. People arrive early, carrying baskets and talking about the weather, while the smell of warm bread drifts across the square. By noon most of the stalls are empty, and the farmers pack their carts and drive slowly home along the river road.",
        "A fisherman named Arlo kept a small green boat tied to a wooden post near the harbor. Each evening he checked the ropes, cleaned the deck, and wrote a few lines in a notebook about the tide and the wind. His neighbors said he could tell when a storm was coming long before the clouds appeared over the hills.",
        "Learning to cook takes patience more than talent. The first few meals may be too salty or a little burned, but every mistake teaches something useful. Good cooks taste as they go, keep their knives sharp, and clean the kitchen while the soup is still simmering, so the work never piles up at the end.",
        "The library on the hill was quiet in the afternoon. Students sat at long tables with their books open, and the only sounds were pages turning and the soft hum of the lamps. An old librarian walked between the shelves, placing returned books back in their proper places without ever looking at the labels.",
        "Walking in the forest after rain is a calm experience. The air smells of wet leaves and earth, and drops of water fall from the branches whenever the wind moves through the trees. Small birds return to the path to look for food, and the light comes through the clouds in thin gold lines.",
        "Many people keep a garden for the simple pleasure of watching things grow. Tomatoes climb their wooden stakes, beans twist around strings, and flowers open slowly as summer arrives. A garden also teaches waiting, because nothing can be rushed, and every season brings its own work and its own reward.",
        "The night train left the station quietly while most passengers were already asleep. Through the window, small villages passed by in the dark, each one marked by a few yellow lights. A conductor walked through the carriages, checking tickets in a low voice so that no one would wake.",
        "Building a habit is easier when the first step is very small. Instead of promising to read for an hour, read a single page before bed. Instead of running a long distance, put on your shoes and walk to the corner. Small steps feel easy, and easy steps are the ones people keep taking.",
    ]

    public static let clips: [Clip] = [
        Clip(id: "a-short", name: "Short sentence", voice: nil,
             script: "Please remember to water the plants on the balcony before you leave for the weekend."),
        Clip(id: "a-british", name: "British voice", voice: "Daniel", script: paragraphs[2]),
        Clip(id: "a-indian", name: "Indian voice", voice: "Aman", script: paragraphs[3]),
        Clip(id: "a-minute", name: "About half a minute", voice: nil, script: paragraphs[0]),
        Clip(id: "a-long", name: "About two minutes", voice: nil, script: paragraphs[4...7].joined(separator: " ")),
        Clip(id: "a-very-long", name: "About four minutes", voice: nil, script: paragraphs.joined(separator: " ")),
        Clip(id: "a-question", name: "Answer from audio", voice: nil, script: paragraphs[1],
             question: (prompt: "Listen to the recording, then answer in one word: what color was the boat?", answer: "green")),
    ]

    public static let transcriptPrompt = "Transcribe this recording exactly. Reply with only the words spoken, nothing else."

    /// A transcript passes when at most this share of its words are wrong.
    public static let passingErrorRate = 0.15

    /// The share of words wrong: substitutions, insertions, and deletions, over the words spoken.
    /// The same measure as the Open ASR Leaderboard's word error rate.
    public static func wordErrorRate(reference: String, hypothesis: String) -> Double {
        let expected = words(reference)
        let heard = words(withoutPreamble(hypothesis))
        guard !expected.isEmpty else { return heard.isEmpty ? 0 : 1 }
        var previous = Array(0...heard.count)
        for (i, word) in expected.enumerated() {
            var current = [i + 1] + Array(repeating: 0, count: heard.count)
            for j in 0..<heard.count {
                current[j + 1] = min(previous[j + 1] + 1, current[j] + 1, previous[j] + (word == heard[j] ? 0 : 1))
            }
            previous = current
        }
        return Double(previous[heard.count]) / Double(expected.count)
    }

    static func words(_ text: String) -> [String] {
        let cleaned = text.lowercased().replacingOccurrences(of: "’", with: "'")
            .unicodeScalars.map { CharacterSet.alphanumerics.contains($0) || $0 == "'" ? Character($0) : " " }
        return String(cleaned).split(separator: " ").map(String.init)
    }

    /// Drops a lead-in line like "Here is the transcript:", which isn't part of what was said.
    static func withoutPreamble(_ text: String) -> String {
        let lines = text.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: "\n", omittingEmptySubsequences: false)
        guard lines.count > 1, let first = lines.first, first.trimmingCharacters(in: .whitespaces).hasSuffix(":") else { return text }
        return lines.dropFirst().joined(separator: "\n")
    }

    /// Turns a clip into a test, once its audio has been made.
    public static func labCase(_ clip: Clip, audioBase64: String) -> LabCase {
        if let question = clip.question {
            return LabCase(id: clip.id, area: .audio, name: clip.name, prompt: question.prompt,
                           promptSummary: "A recording of a short story, then: \(question.prompt)",
                           audioBase64: audioBase64, expected: question.answer.capitalized,
                           grade: LabGrade.hasWord(question.answer))
        }
        return LabCase(id: clip.id, area: .audio, name: clip.name, prompt: transcriptPrompt,
                       promptSummary: "\(clip.name): “\(clip.script.prefix(90))…”",
                       audioBase64: audioBase64, maxTokens: max(400, words(clip.script).count * 3),
                       expected: "At least \(Int((1 - passingErrorRate) * 100))% of words right",
                       grade: { wordErrorRate(reference: clip.script, hypothesis: $0.text) <= passingErrorRate })
    }
}
