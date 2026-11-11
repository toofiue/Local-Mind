import Foundation
import Testing
@testable import LanternKit

private func report(_ name: String, tps: Double, audio: [Bool], reasoning: [Bool]) -> LabReport {
    let results = audio.enumerated().map { LabCaseResult(id: "a\($0.offset)", area: .audio, name: "x", reply: "", passed: $0.element) }
        + reasoning.enumerated().map { LabCaseResult(id: "r\($0.offset)", area: .reasoning, name: "x", reply: "", passed: $0.element) }
    return LabReport(modelName: name, date: .now, tokensPerSecond: tps, loadSeconds: 1, memoryBytes: 1, swapGrowthBytes: 0,
                     totalMemoryBytes: 1, supportsImages: false, supportsTools: false, results: results, supportsAudio: !audio.isEmpty)
}

@Test("S-052 the highest score wins each area")
func picksHighestScore() {
    let winners = LabLeaderboard.winners([
        report("slow-smart", tps: 10, audio: [true, true, true], reasoning: [true, false]),
        report("fast-deaf", tps: 40, audio: [], reasoning: [true, true]),
    ])
    #expect(winners.first { $0.area == .audio }?.modelName == "slow-smart")
    #expect(winners.first { $0.area == .reasoning }?.modelName == "fast-deaf")
    #expect(winners.first { $0.area == .speed }?.modelName == "fast-deaf")
}

@Test("S-052 the faster model wins a tie")
func breaksTiesBySpeed() {
    let winners = LabLeaderboard.winners([
        report("a", tps: 12, audio: [true, false], reasoning: []),
        report("b", tps: 30, audio: [true, false], reasoning: []),
    ])
    #expect(winners.first { $0.area == .audio }?.modelName == "b")
}

@Test("S-052 untested areas have no winner")
func skipsUntested() {
    #expect(LabLeaderboard.winners([report("a", tps: 0, audio: [], reasoning: [true])]).map(\.area) == [.reasoning])
}
