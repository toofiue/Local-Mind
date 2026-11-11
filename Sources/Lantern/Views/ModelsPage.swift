import SwiftUI
import LanternKit

/// Every installed model as a card, with which one is best at each job on top.
struct ModelsPage: View {
    /// Shown as the Models section of Settings: sized for the board, with no window title or toolbar.
    var inSettings = false
    @Environment(AppModel.self) private var model
    @State private var renaming: OllamaModel?

    private var winners: [LabLeaderboard.Winner] {
        LabLeaderboard.winners(model.models.compactMap { model.labReports[$0.name] })
    }

    private var testedCount: Int { model.models.filter { model.labReports[$0.name] != nil }.count }

    var body: some View {
        if inSettings {
            content
        } else {
            content
                .navigationTitle("Models")
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        Button("New Conversation", systemImage: "square.and.pencil") { model.newConversation() }
                            .help("Start a new conversation (⌘N)")
                    }
                }
        }
    }

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: inSettings ? Space.xl : Space.section) {
                header
                // Your models first, then which one won each job.
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 280), spacing: Space.lg, alignment: .top)],
                          alignment: .leading, spacing: Space.lg) {
                    ForEach(model.models) { item in
                        ModelCard(item: item, onRename: { renaming = item })
                    }
                }
                bestFor
            }
            .padding(.horizontal, inSettings ? Space.xxl : Space.margin)
            .padding(.vertical, inSettings ? Space.xl : Space.margin)
            // Room to breathe on a big window, without lines too long to scan.
            .frame(maxWidth: 1280, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .overlay {
            if model.models.isEmpty { NoModelsView() }
        }
        .sheet(item: $renaming) { RenameModelSheet(item: $0) }
        .task {
            for item in model.models { model.loadLabReport(item.name) }
        }
    }

    @ViewBuilder private var header: some View {
        VStack(alignment: .leading, spacing: Space.md) {
            HStack(alignment: .firstTextBaseline) {
                Text(model.models.count == 1 ? "1 model on this Mac" : "\(model.models.count) models on this Mac")
                    .font(inSettings ? .title3 : TextStyle.title)
                Spacer()
                if model.lab.isRunning {
                    Button("Stop") { model.stop() }
                } else {
                    Button("Test All Models") { model.testAllModels() }
                        .disabled(model.isWriting || model.connection != .connected || model.models.isEmpty)
                        .help("Run the quick check on every model, one at a time. This can take a while.")
                }
            }
            ModelDefaults()
            if model.lab.isRunning {
                VStack(alignment: .leading, spacing: Space.xs) {
                    ProgressView(value: Double(model.lab.completed), total: Double(max(model.lab.total, 1)))
                    Text(model.labQueue.isEmpty
                         ? "Testing \(model.displayName(model.lab.modelName ?? ""))"
                         : "Testing \(model.displayName(model.lab.modelName ?? "")) · \(model.labQueue.count) more after this")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    @ViewBuilder private var bestFor: some View {
        if !winners.isEmpty {
            VStack(alignment: .leading, spacing: Space.md) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Best For").font(TextStyle.heading)
                    if testedCount < model.models.count {
                        Text("From \(testedCount) of \(model.models.count) models tested")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                // Tiles wrap onto more rows instead of running off the edge.
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 168), spacing: Space.sm, alignment: .top)],
                          alignment: .leading, spacing: Space.sm) {
                        ForEach(winners, id: \.area) { winner in
                            VStack(alignment: .leading, spacing: Space.xs) {
                                Label(winner.area.title, systemImage: winner.area.symbol)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text(model.displayName(winner.modelName))
                                    .font(.callout.weight(.medium))
                                    .lineLimit(1)
                                Text(score(winner))
                                    .font(.caption)
                                    .foregroundStyle(Palette.accentText)
                                    .monospacedDigit()
                            }
                            .padding(Space.md)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(.fill.quaternary, in: RoundedRectangle(cornerRadius: Radius.md))
                        }
                }
            }
        }
    }

    private func score(_ winner: LabLeaderboard.Winner) -> String {
        winner.area == .speed
            ? "\(Int(winner.tokensPerSecond.rounded())) tokens per second"
            : "\(winner.passed) of \(winner.total) passed"
    }
}

/// One model: whether it's in memory, its score, what it can do, and what to do next.
private struct ModelCard: View {
    let item: OllamaModel
    let onRename: () -> Void
    @Environment(AppModel.self) private var model

    private var report: LabReport? { model.labReports[item.name] }
    private var memory: Int64? { model.loaded.first { $0.name == item.name }?.memory }
    private var isLoaded: Bool { memory != nil }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.md) {
            HStack(spacing: Space.sm) {
                Image(nsImage: ApertureIcon.image(isLoaded ? .open : .closed))
                    .foregroundStyle(isLoaded ? AnyShapeStyle(Palette.accentText) : AnyShapeStyle(.tertiary))
                    .help(isLoaded ? "In memory, ready to reply" : "Not in memory. It loads when you use it.")
                VStack(alignment: .leading, spacing: 0) {
                    Text(model.displayName(item.name)).font(TextStyle.heading).lineLimit(1)
                    if model.modelNicknames[item.name] != nil {
                        Text(item.name).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                Spacer()
                Menu { actions } label: { Image(systemName: "ellipsis") }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .fixedSize()
                    .help("More actions for this model")
                    .accessibilityLabel("More actions for \(model.displayName(item.name))")
            }
            // A fixed-height score line, so every card is the same height.
            HStack(alignment: .lastTextBaseline, spacing: Space.sm) {
                if let report {
                    Text("\(report.totalPassed)").font(.system(.largeTitle, design: .serif))
                    Text("of \(report.results.count) passed").font(.callout).foregroundStyle(.secondary)
                } else {
                    Text("Not tested yet").font(.callout).foregroundStyle(.secondary)
                }
            }
            .frame(height: 40, alignment: .bottomLeading)
            HStack(spacing: Space.sm) {
                ForEach(item.abilities, id: \.self) { title in
                    Image(systemName: Self.symbol(title))
                        .foregroundStyle(.secondary)
                        .help(title)
                        .accessibilityLabel(title)
                }
                Spacer()
                if let memory {
                    Text("\(ByteCountFormatter.string(fromByteCount: memory, countStyle: .file)) in memory")
                        .font(.caption)
                        .foregroundStyle(Palette.accentText)
                } else {
                    Text(ByteCountFormatter.string(fromByteCount: item.size, countStyle: .file))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            HStack {
                Button(report == nil ? "Test This Model" : "See Results") { model.openLab(item.name) }
                    .help("Find out what this model is good at")
                if isLoaded {
                    Button("Unload") { Task { await model.unload(item.name) } }
                        .disabled(!model.canUnload(item.name))
                        .help("Free the memory this model is using")
                }
            }
        }
        .padding(Space.lg)
        .background(.fill.quinary, in: RoundedRectangle(cornerRadius: Radius.lg))
        .overlay(RoundedRectangle(cornerRadius: Radius.lg)
            .strokeBorder(isLoaded ? AnyShapeStyle(Palette.accent.opacity(0.5)) : AnyShapeStyle(.separator)))
        .contextMenu { actions }
    }

    @ViewBuilder private var actions: some View {
        Button("Rename…", action: onRename)
        Button(report == nil ? "Test" : "See Results") { model.openLab(item.name) }
        if isLoaded {
            Divider()
            Button("Unload") { Task { await model.unload(item.name) } }
                .disabled(!model.canUnload(item.name))
        }
    }

    static func symbol(_ title: String) -> String {
        switch title {
        case "Images": "photo"
        case "Audio": "waveform"
        case "Thinking": "brain"
        default: "wrench.and.screwdriver"
        }
    }
}

extension LabArea {
    var symbol: String {
        switch self {
        case .speed: "gauge.with.dots.needle.67percent"
        case .reasoning: "function"
        case .code: "chevron.left.forwardslash.chevron.right"
        case .instructions: "list.bullet.clipboard"
        case .data: "tablecells"
        case .documents: "doc.text"
        case .images: "photo"
        case .audio: "waveform"
        case .tools: "wrench.and.screwdriver"
        }
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
                .font(TextStyle.heading)
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


/// How models are used, kept with the models themselves: which one new conversations start with,
/// and how long one stays in memory after replying.
private struct ModelDefaults: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        HStack(spacing: Space.xl) {
            HStack(spacing: Space.sm) {
                Text("New conversations use").foregroundStyle(.secondary)
                Picker("New conversations use", selection: $model.chosenDefaultModel) {
                    Text("Last Used").tag("")
                    Divider()
                    ForEach(model.models) { item in
                        Text(model.displayName(item.name)).tag(item.name)
                    }
                }
                .labelsHidden()
                .fixedSize()
                .help("The model a new conversation starts with. Last Used picks the one you used most recently.")
            }
            HStack(spacing: Space.sm) {
                Text("Keep loaded for").foregroundStyle(.secondary)
                Picker("Keep loaded for", selection: $model.keepLoadedMinutes) {
                    ForEach([1, 5, 15, 30], id: \.self) { minutes in
                        Text("^[\(minutes) minute](inflect: true)").tag(minutes)
                    }
                }
                .labelsHidden()
                .fixedSize()
                .help("How long a model stays in memory after its last reply. Loaded models answer at once but use a lot of memory.")
            }
        }
        .font(.callout)
    }
}
