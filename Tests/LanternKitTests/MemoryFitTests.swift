import Testing
@testable import LanternKit

private let gigabyte: Int64 = 1_073_741_824
private func memory(total: Int64, free: Int64) -> MemorySnapshot {
    MemorySnapshot(totalBytes: total * gigabyte, availableBytes: free * gigabyte)
}

@Test("S-039 a model with room to spare is comfortable")
func comfortable() {
    #expect(MemoryAdvisor.assess(modelSize: 8 * gigabyte, memory: memory(total: 16, free: 12)) == .comfortable)
}

@Test("S-039 a model that fits this Mac but not right now asks to close apps")
func closeApps() {
    let fit = MemoryAdvisor.assess(modelSize: 8 * gigabyte, memory: memory(total: 16, free: 6))
    guard case .closeApps = fit else { Issue.record("got \(fit)"); return }
}

@Test("S-039 a model nearly as big as the Mac's memory is too large")
func tooLarge() {
    let fit = MemoryAdvisor.assess(modelSize: 15 * gigabyte, memory: memory(total: 16, free: 15))
    guard case .tooLarge = fit else { Issue.record("got \(fit)"); return }
}

@Test("S-039 memory held by another loaded model counts as free")
func countsFreeable() {
    #expect(MemoryAdvisor.assess(modelSize: 8 * gigabyte, memory: memory(total: 16, free: 4), freeable: 8 * gigabyte) == .comfortable)
}

@Test("S-039 the 13.79 GB model is a tight fit on 16 GB, not impossible")
func gptOnSixteen() {
    let fit = MemoryAdvisor.assess(modelSize: 13_790_000_000, memory: memory(total: 16, free: 6))
    guard case .closeApps = fit else { Issue.record("got \(fit)"); return }
}
