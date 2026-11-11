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
        /// Words per minute, or nil for the voice's normal pace.
        public var rate: Int? = nil
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

    /// More paragraphs, so the longest clip runs past four minutes without repeating itself.
    static let moreParagraphs = [
        "Rain had fallen all night on the mountain village, and by morning the narrow streets shone like polished stone. A baker opened his shutters, and the smell of cinnamon rolls reached the children waiting for the school bus at the corner.",
        "The old bridge over the canal creaks whenever a cart rolls across it. Engineers have promised to repair it for years, but the town council keeps choosing new benches for the park instead, and nobody seems to mind very much.",
        "My grandmother kept her recipes in a tin box painted with blue flowers. Each card was stained with butter and flour, and the handwriting changed over the decades from careful loops to quick, slanted notes in the margins.",
        "At the edge of the desert, the wind carries sand across the highway in thin, shifting ribbons. Drivers slow down, turn on their lights, and follow the red glow of the truck ahead until the air clears near the mountains.",
        "The orchestra tuned their instruments while the audience found their seats. A violinist adjusted her chair, the cellist closed his eyes, and the conductor waited in silence until the whole hall seemed to hold its breath.",
        "Every spring, the river floods the low meadow and leaves behind a layer of dark, rich soil. Farmers wait until the ground is firm enough to walk on, then plant corn and squash in long rows that stretch toward the woods.",
        "A lighthouse keeper once lived alone on the rocky island beyond the bay. He painted watercolors of passing ships, wrote long letters to his sister, and kept the great lamp burning through every storm of the winter.",
        "The museum opened a new hall filled with ancient maps. Visitors leaned close to the glass, tracing coastlines that were drawn by hand, with sea monsters curling in the corners where the sailors had never traveled.",
        "Learning a new language feels slow at first. You repeat the same simple phrases, forget words you knew yesterday, and blush when you order the wrong meal. Then one day a joke makes sense, and everything starts to change.",
        "The mechanic wiped his hands on a cloth and listened to the engine for a long moment. He said the noise came from a loose belt, tightened it in a few minutes, and refused to charge more than the price of a coffee.",
    ]

    public static let clips: [Clip] = [
        Clip(id: "a-short", name: "Short sentence", voice: nil,
             script: "Please remember to water the plants on the balcony before you leave for the weekend."),
        Clip(id: "a-british", name: "British voice", voice: "Daniel", script: paragraphs[2]),
        Clip(id: "a-indian", name: "Indian voice", voice: "Aman", script: paragraphs[3]),
        Clip(id: "a-fast", name: "Fast speech", voice: nil, script: paragraphs[5], rate: 320),
        Clip(id: "a-minute", name: "About 20 seconds", voice: nil, script: paragraphs[0]),
        Clip(id: "a-long", name: "About a minute", voice: nil, script: paragraphs[4...7].joined(separator: " ")),
        Clip(id: "a-very-long", name: "About two minutes", voice: nil, script: paragraphs.joined(separator: " ")),
        Clip(id: "a-longest", name: "Over four minutes", voice: nil, script: (paragraphs + moreParagraphs).joined(separator: " ")),
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
