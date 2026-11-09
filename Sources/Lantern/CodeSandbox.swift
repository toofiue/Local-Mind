import Foundation

/// Runs Python a model wrote, for HumanEval, inside a macOS sandbox with no
/// network, no file writes, no way to start other programs, and no access to
/// your personal files. A run that takes too long is killed.
enum CodeSandbox {
    nonisolated private static let python = "/usr/bin/python3"
    nonisolated private static let toolsPython = "/Library/Developer/CommandLineTools/usr/bin/python3"
    nonisolated private static let xcodePython = "/Applications/Xcode.app/Contents/Developer/usr/bin/python3"

    /// Checked first, because /usr/bin/python3 offers to install tools if none exist.
    nonisolated static var isAvailable: Bool {
        FileManager.default.isExecutableFile(atPath: toolsPython) || FileManager.default.isExecutableFile(atPath: xcodePython)
    }

    nonisolated private static let profile = """
    (version 1)
    (allow default)
    (deny network*)
    (deny file-write*)
    (allow file-write* (literal "/dev/null") (literal "/dev/dtracehelper"))
    (deny process-fork)
    (deny file-read* (subpath "/Users"))
    """

    /// True only if the program finishes cleanly within the time limit.
    nonisolated static func passes(_ program: String, timeout: Double = 10) -> Bool {
        guard isAvailable else { return false }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sandbox-exec")
        // -I keeps the current folder and environment out of Python's import path.
        process.arguments = ["-p", profile, python, "-B", "-I", "-"]
        process.currentDirectoryURL = URL(fileURLWithPath: "/private/tmp")
        process.environment = ["PATH": "/usr/bin:/bin", "HOME": "/private/tmp"]
        let input = Pipe()
        process.standardInput = input
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        let finished = DispatchSemaphore(value: 0)
        process.terminationHandler = { @Sendable _ in finished.signal() }
        do {
            try process.run()
        } catch {
            return false
        }
        input.fileHandleForWriting.write(Data(program.utf8))
        try? input.fileHandleForWriting.close()
        if finished.wait(timeout: .now() + timeout) == .timedOut {
            kill(process.processIdentifier, SIGKILL)
            finished.wait()
            return false
        }
        return process.terminationReason == .exit && process.terminationStatus == 0
    }
}
