import Foundation

/// This Mac's memory right now, in bytes.
public struct MemorySnapshot: Sendable, Equatable {
    public let totalBytes: Int64
    public let availableBytes: Int64

    public init(totalBytes: Int64, availableBytes: Int64) {
        self.totalBytes = totalBytes
        self.availableBytes = availableBytes
    }
}

public enum MemoryFit: Sendable, Equatable {
    case comfortable
    /// It fits on this Mac, but not alongside what's running now.
    case closeApps(neededBytes: Int64, availableBytes: Int64)
    /// It barely fits, or doesn't, even with nothing else running.
    case tooLarge(neededBytes: Int64)
}

public enum MemoryAdvisor {
    /// What macOS needs for itself, on top of the model.
    public static let systemReserve: Int64 = 2_147_483_648
    /// How much more macOS can free by compressing memory, without the Mac slowing down noticeably.
    public static let reclaimable: Int64 = 2_147_483_648

    /// A loaded model measured within 1% of its size on disk.
    public static func estimatedNeed(modelSize: Int64) -> Int64 {
        modelSize
    }

    /// `freeable` is memory that loading this model will release, such as another loaded model.
    public static func assess(modelSize: Int64, memory: MemorySnapshot, freeable: Int64 = 0) -> MemoryFit {
        let needed = estimatedNeed(modelSize: modelSize)
        if needed + systemReserve > memory.totalBytes { return .tooLarge(neededBytes: needed) }
        let available = memory.availableBytes + freeable
        if needed > available + reclaimable { return .closeApps(neededBytes: needed, availableBytes: available) }
        return .comfortable
    }
}
