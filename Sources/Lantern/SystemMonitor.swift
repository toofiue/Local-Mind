import AppKit
import Darwin
import LanternKit

/// Reads this Mac's specs and memory use. Everything stays on this Mac.
enum SystemMonitor {
    struct AppMemory: Equatable {
        let name: String
        let bytes: Int64
    }

    static var chipName: String {
        var size = 0
        guard sysctlbyname("machdep.cpu.brand_string", nil, &size, nil, 0) == 0, size > 0 else { return "This Mac" }
        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname("machdep.cpu.brand_string", &buffer, &size, nil, 0) == 0 else { return "This Mac" }
        return String(cString: buffer)
    }

    static func memory() -> MemorySnapshot {
        let total = Int64(ProcessInfo.processInfo.physicalMemory)
        var statistics = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.stride / MemoryLayout<integer_t>.stride)
        let result = withUnsafeMutablePointer(to: &statistics) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return MemorySnapshot(totalBytes: total, availableBytes: total) }
        // Inactive, speculative, and purgeable pages are given back as soon as something needs them.
        let pages = Int64(statistics.free_count) + Int64(statistics.inactive_count)
            + Int64(statistics.speculative_count) + Int64(statistics.purgeable_count)
        return MemorySnapshot(totalBytes: total, availableBytes: pages * Int64(sysconf(_SC_PAGESIZE)))
    }

    static func swapUsedBytes() -> Int64 {
        var usage = xsw_usage()
        var size = MemoryLayout<xsw_usage>.size
        guard sysctlbyname("vm.swapusage", &usage, &size, nil, 0) == 0 else { return 0 }
        return Int64(usage.xsu_used)
    }

    /// The apps you could close that are using the most memory.
    static func topApps(limit: Int = 3) -> [AppMemory] {
        let ownID = ProcessInfo.processInfo.processIdentifier
        let apps = NSWorkspace.shared.runningApplications.filter {
            $0.activationPolicy == .regular && $0.processIdentifier != ownID && $0.localizedName != "Ollama"
        }
        let measured = apps.compactMap { app -> AppMemory? in
            guard let name = app.localizedName else { return nil }
            var info = rusage_info_v4()
            let result = withUnsafeMutablePointer(to: &info) { pointer in
                pointer.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) {
                    proc_pid_rusage(app.processIdentifier, RUSAGE_INFO_V4, $0)
                }
            }
            guard result == 0 else { return nil }
            return AppMemory(name: name, bytes: Int64(info.ri_phys_footprint))
        }
        return Array(measured.filter { $0.bytes >= 314_572_800 }.sorted { $0.bytes > $1.bytes }.prefix(limit))
    }
}
