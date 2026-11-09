import Foundation
import LanternKit

struct MemoryWarning: Equatable {
    enum Surface { case main, quickAsk, lab }

    let modelName: String
    let surface: Surface
    let message: String
    /// The apps using the most memory, or empty if none stand out.
    let appsSummary: String
}

extension AppModel {
    private func bytes(_ value: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: value, countStyle: .file)
    }

    /// A warning if loading this model now would strain the Mac, or nil if it fits.
    func memoryWarningIfNeeded(for modelName: String, surface: MemoryWarning.Surface) -> MemoryWarning? {
        guard !loaded.contains(where: { $0.name == modelName }),
              let installed = models.first(where: { $0.name == modelName }) else { return nil }
        let freeable = loaded.reduce(0) { $0 + $1.memory }
        let fit = MemoryAdvisor.assess(modelSize: installed.size, memory: readMemory(), freeable: freeable)
        let name = displayName(modelName)
        let message: String
        switch fit {
        case .comfortable:
            return nil
        case .closeApps(let needed, let available):
            message = "\(name) needs about \(bytes(needed)), and \(bytes(available)) is free. Close other apps to keep your Mac responsive."
        case .tooLarge(let needed):
            message = "\(name) needs about \(bytes(needed)), which is nearly all of this Mac's memory. It may be very slow or fail to load."
        }
        let apps = readTopApps().map { "\($0.name) (\(bytes($0.bytes)))" }.joined(separator: ", ")
        return MemoryWarning(modelName: modelName, surface: surface, message: message,
                             appsSummary: apps.isEmpty ? "" : "Using the most memory: \(apps)")
    }

    /// Looks again after you've closed something. The warning clears if the model now fits.
    func recheckMemory() {
        guard let current = memoryWarning else { return }
        memoryWarning = memoryWarningIfNeeded(for: current.modelName, surface: current.surface)
    }
}
