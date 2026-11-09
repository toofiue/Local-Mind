import SwiftUI
import LanternKit

/// Every installed model, and which one is using memory.
struct ModelsPage: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        List(model.models) { item in
            ModelRow(item: item, loaded: model.loaded.first { $0.name == item.name })
        }
        .overlay {
            if model.models.isEmpty { NoModelsView() }
        }
        .navigationTitle("Models")
    }
}

private struct ModelRow: View {
    let item: OllamaModel
    let loaded: LoadedModel?
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(spacing: Space.lg) {
            VStack(alignment: .leading, spacing: Space.xs) {
                Text(item.name)
                Text(item.capabilitySummary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: Space.lg)
            if let loaded {
                Label {
                    Text("Loaded · \(loaded.memory, format: .byteCount(style: .file))")
                } icon: {
                    Image(systemName: "memorychip.fill")
                }
                .font(.callout)
                .foregroundStyle(Palette.accentText)
            }
            Text(item.size, format: .byteCount(style: .file))
                .foregroundStyle(.secondary)
                .monospacedDigit()
            if loaded != nil {
                Button("Unload") { Task { await model.unload(item.name) } }
                    .disabled(!model.canUnload(item.name))
                    .help(model.canUnload(item.name) ? "Free the memory this model is using" : "Unavailable while this model is writing a reply")
                    .accessibilityLabel("Unload \(item.name)")
            }
        }
        .padding(.vertical, Space.xs)
    }
}
