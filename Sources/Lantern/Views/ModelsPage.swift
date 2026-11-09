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
    @State private var isNaming = false
    @State private var draft = ""
    @FocusState private var fieldIsFocused: Bool

    var body: some View {
        HStack(spacing: Space.lg) {
            VStack(alignment: .leading, spacing: Space.xs) {
                if isNaming {
                    TextField("Model name", text: $draft, prompt: Text(item.name))
                        .labelsHidden()
                        .focused($fieldIsFocused)
                        .onSubmit { save() }
                        .onExitCommand { isNaming = false }
                        .frame(maxWidth: Layout.chip)
                        .task {
                            // A list row can't take focus until it has been laid out.
                            try? await Task.sleep(for: .milliseconds(50))
                            fieldIsFocused = true
                        }
                } else {
                    ModelNameLabel(name: item.name)
                }
                Text(item.capabilitySummary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Button("Name This Model", systemImage: "pencil") {
                draft = model.modelNicknames[item.name] ?? ""
                isNaming = true
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
            .help("Give this model your own name")
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

    private func save() {
        model.setNickname(draft, for: item.name)
        isNaming = false
    }
}
