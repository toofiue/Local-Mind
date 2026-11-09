import SwiftUI

/// Shown when Ollama is running but has no models.
struct NoModelsView: View {
    private let command = "ollama pull gemma4"
    @State private var didCopy = false

    var body: some View {
        ContentUnavailableView {
            Label("No Models Installed", systemImage: "cpu")
        } description: {
            Text("Install one in Terminal. It appears here when you come back.")
        } actions: {
            HStack(spacing: Space.md) {
                Text(command)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
                    .fixedSize()
                Button(didCopy ? "Copied" : "Copy") {
                    Clipboard.copy(command)
                    didCopy = true
                    Task {
                        try? await Task.sleep(for: Motion.confirmation)
                        didCopy = false
                    }
                }
            }
        }
    }
}
