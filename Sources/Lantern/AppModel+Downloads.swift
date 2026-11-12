import AppKit
import LanternKit

/// Getting models without the Terminal: downloads through Ollama with progress, and removing them.
extension AppModel {
    var totalMemory: Int64 { readMemory().totalBytes }

    func isInstalled(_ name: String) -> Bool {
        ModelCatalog.isInstalled(name, in: models.map(\.name))
    }

    /// Starts a download. It keeps going while you use the app; Ollama resumes it if it's interrupted.
    func download(_ name: String) {
        guard downloads[name] == nil else { return }
        downloadErrors[name] = nil
        downloads[name] = PullProgress(fraction: nil, step: "Starting")
        downloadTasks[name] = Task {
            do {
                for try await progress in client.pull(name) {
                    downloads[name] = progress
                }
                downloads[name] = nil
                downloadTasks[name] = nil
                await refreshInstalledModels()
            } catch is CancellationError {
                downloads[name] = nil
                downloadTasks[name] = nil
            } catch {
                downloads[name] = nil
                downloadTasks[name] = nil
                downloadErrors[name] = (error as? OllamaError).map(Self.plainDownloadError) ?? "The download stopped. Try again."
            }
        }
    }

    func cancelDownload(_ name: String) {
        downloadTasks[name]?.cancel()
        downloadTasks[name] = nil
        downloads[name] = nil
    }

    /// Removes a model from this Mac, after freeing its memory if it's loaded.
    func deleteModel(_ name: String) async {
        if loaded.contains(where: { $0.name == name }) { await unload(name) }
        do {
            try await client.delete(name)
        } catch {
            attachmentNotice = "Couldn't remove \(displayName(name)). Try again in a moment."
        }
        await refreshInstalledModels()
        if chosenDefaultModel == name { chosenDefaultModel = "" }
    }

    private static func plainDownloadError(_ error: OllamaError) -> String {
        switch error {
        case .unreachable: "Ollama stopped responding. Check your internet connection and try again."
        case .server(let message) where message.contains("does not exist"): "Ollama's library doesn't have this model any more."
        case .server(let message) where message.lowercased().contains("space"): "Not enough disk space for this model."
        default: "The download stopped. Try again."
        }
    }

    // MARK: Ollama itself

    /// Whether the Ollama app is on this Mac, in either Applications folder.
    static var ollamaInstalled: Bool {
        if let pretend = pretendOllamaInstalled { return pretend }
        let places = ["/Applications/Ollama.app", NSHomeDirectory() + "/Applications/Ollama.app"]
        return places.contains { FileManager.default.fileExists(atPath: $0) }
            || FileManager.default.isExecutableFile(atPath: "/usr/local/bin/ollama")
            || FileManager.default.isExecutableFile(atPath: "/opt/homebrew/bin/ollama")
    }

    /// Snapshots set this to show the Get Ollama screen on a Mac that has Ollama.
    nonisolated(unsafe) static var pretendOllamaInstalled: Bool?

    static let ollamaDownloadPage = URL(string: "https://ollama.com/download")!
}
