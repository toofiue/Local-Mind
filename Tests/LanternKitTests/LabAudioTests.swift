import Testing
@testable import LanternKit

@Test("S-051 a perfect transcript has no errors")
func perfectTranscript() {
    #expect(LabAudio.wordErrorRate(reference: "The cat sat.", hypothesis: "the cat sat") == 0)
}

@Test("S-051 wrong, missing, and extra words all count")
func countsErrors() {
    let reference = "one two three four five six seven eight nine ten"
    #expect(LabAudio.wordErrorRate(reference: reference, hypothesis: "one two three four five six seven eight nine tin") == 0.1)
    #expect(LabAudio.wordErrorRate(reference: reference, hypothesis: "one two three four five six seven eight nine") == 0.1)
    #expect(LabAudio.wordErrorRate(reference: reference, hypothesis: "one two three four five six seven eight nine ten eleven") == 0.1)
    #expect(LabAudio.wordErrorRate(reference: reference, hypothesis: "") == 1)
}

@Test("S-051 a lead-in line like 'Here is the transcript:' isn't counted")
func ignoresPreamble() {
    #expect(LabAudio.wordErrorRate(reference: "Hello there friend.", hypothesis: "Here is the transcript:\n\"Hello there, friend.\"") == 0)
}

@Test("S-051 every clip has words to check and no numbers")
func clipsAreCheckable() {
    for clip in LabAudio.clips {
        #expect(!LabAudio.words(clip.script).isEmpty, "\(clip.id)")
        #expect(!clip.script.contains { $0.isNumber }, "\(clip.id) has a number")
    }
    let longest = LabAudio.clips.map { LabAudio.words($0.script).count }.max() ?? 0
    #expect(longest > 400)
}

@Test("S-051 audio tests only run for models that can listen")
func audioCasesNeedAudio() {
    let audio = Dictionary(uniqueKeysWithValues: LabAudio.clips.map { ($0.id, "UklGRg==") })
    let listener = OllamaModel(name: "a", size: 1, capabilities: ["audio"])
    let deaf = OllamaModel(name: "b", size: 1, capabilities: ["completion"])
    #expect(ModelLab.cases(for: listener, audio: audio).filter { $0.area == .audio }.count == LabAudio.clips.count)
    #expect(ModelLab.cases(for: deaf, audio: audio).allSatisfy { $0.area != .audio })
}

@Test("S-051 a good transcript passes and a poor one fails")
func gradesTranscripts() throws {
    let clip = try #require(LabAudio.clips.first { $0.id == "a-short" })
    let test = LabAudio.labCase(clip, audioBase64: "")
    #expect(test.grade(LabResponse(text: clip.script)))
    #expect(!test.grade(LabResponse(text: "Please water the plants.")))
}
