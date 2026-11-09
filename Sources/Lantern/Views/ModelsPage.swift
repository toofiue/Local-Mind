import SwiftUI
import LanternKit

/// Every installed model, what's in memory, and what's been tested.
struct ModelsPage: View {
    @Environment(AppModel.self) private var model
    @State private var renaming: OllamaModel?

    private var inMemory: [OllamaModel] {
        model.models.filter { item in model.loaded.contains { $0.name == item.name } }
    }

    private var notLoaded: [OllamaModel] {
        model.models.filter { item in !model.loaded.contains { $0.name == item.name } }
    }

    var body: some View {
        Form {
            if !inMemory.isEmpty {
                Section("In Memory") { rows(inMemory) }
            }
            if !notLoaded.isEmpty {
                Section("Installed") { rows(notLoaded) }
            }
        }
        .formStyle(.grouped)
        .overlay {
            if model.models.isEmpty { NoModelsView() }
        }
        .navigationTitle("Models")
        .sheet(item: $renaming) { item in
            RenameModelSheet(item: item)
        }
        .task {
            for item in model.models { model.loadLabReport(item.name) }
        }
    }

    private func rows(_ items: [OllamaModel]) -> some View {
        ForEach(items) { item in
            ModelRow(item: item, loaded: model.loaded.first { $0.name == item.name }, onRename: { renaming = item })
        }
    }
}

private struct ModelRow: View {
    let item: OllamaModel
    let loaded: LoadedModel?
    let onRename: () -> Void
    @Environment(AppModel.self) private var model

    private var report: LabReport? { model.labReports[item.name] }

    /// The original name, shown in small text when you've chosen your own, then the size.
    private var details: String {
        let size = ByteCountFormatter.string(fromByteCount: item.size, countStyle: .file)
        return model.modelNicknames[item.name] == nil ? size : "\(item.name) · \(size)"
    }

    var body: some View {
        HStack(spacing: Space.md) {
            VStack(alignment: .leading, spacing: Space.xs) {
                Text(model.displayName(item.name))
                    .font(.headline)
                Text(details)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if !item.abilities.isEmpty {
                    HStack(spacing: Space.xs) {
                        ForEach(item.abilities, id: \.self) { AbilityTag(title: $0) }
                    }
                }
            }
            Spacer(minLength: Space.lg)
            if let loaded {
                Label(ByteCountFormatter.string(fromByteCount: loaded.memory, countStyle: .file), systemImage: "memorychip.fill")
                    .font(.callout)
                    .foregroundStyle(Palette.accentText)
                    .help("Using this much memory right now")
                Button("Unload") { Task { await model.unload(item.name) } }
                    .disabled(!model.canUnload(item.name))
                    .help(model.canUnload(item.name) ? "Free the memory this model is using" : "Unavailable while this model is busy")
                    .accessibilityLabel("Unload \(model.displayName(item.name))")
            }
            if let report {
                Text("\(report.totalPassed) of \(report.results.count)")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .help("Tests passed in the last run")
            }
            Button(report == nil ? "Test" : "Results") { model.openLab(item.name) }
                .help("Find out what this model is good at")
            Menu {
                actions
            } label: {
                Label("More", systemImage: "ellipsis")
                    .labelStyle(.iconOnly)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("More actions for this model")
            .accessibilityLabel("More actions for \(model.displayName(item.name))")
        }
        .padding(.vertical, Space.xs)
        .contextMenu { actions }
    }

    @ViewBuilder
    private var actions: some View {
        Button("Rename…", action: onRename)
        Button(report == nil ? "Test" : "See Results") { model.openLab(item.name) }
        if loaded != nil {
            Divider()
            Button("Unload") { Task { await model.unload(item.name) } }
                .disabled(!model.canUnload(item.name))
        }
    }
}

private struct AbilityTag: View {
    let title: String

    private var symbol: String {
        switch title {
        case "Images": "photo"
        case "Audio": "waveform"
        case "Thinking": "brain"
        default: "wrench.and.screwdriver"
        }
    }

    var body: some View {
        Label(title, systemImage: symbol)
            .font(.caption2)
            .foregroundStyle(.secondary)
            .padding(.horizontal, Space.sm)
            .padding(.vertical, 2)
            .background(.fill.tertiary, in: Capsule())
    }
}

/// Gives a model a name of your own.
private struct RenameModelSheet: View {
    let item: OllamaModel
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: Space.lg) {
            Text("Name This Model")
                .font(.headline)
            TextField("Name", text: $name, prompt: Text(item.name))
                .focused($isFocused)
                .onSubmit(save)
            Text("Shown in your conversations and Quick Ask. The original name, \(item.name), stays in the model list.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                if model.modelNicknames[item.name] != nil {
                    Button("Use Original") {
                        model.setNickname("", for: item.name)
                        dismiss()
                    }
                }
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Save", action: save)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(Space.margin)
        .frame(width: Layout.renameSheet)
        .onAppear {
            name = model.modelNicknames[item.name] ?? ""
            isFocused = true
        }
    }

    private func save() {
        model.setNickname(name, for: item.name)
        dismiss()
    }
}
