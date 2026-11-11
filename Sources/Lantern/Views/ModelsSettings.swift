import LanternKit
import SwiftUI

/// Settings > Models, in the same row style as the rest of Settings.
/// Defaults as setting rows, then one row per model with aligned columns, then Best For as a short list.
/// Controls are neutral; the accent marks only a loaded model.
struct ModelsSettings: View {
    @Environment(AppModel.self) private var model
    @State private var renaming: OllamaModel?

    private var winners: [LabLeaderboard.Winner] {
        LabLeaderboard.winners(model.models.compactMap { model.labReports[$0.name] })
    }
    private var testedCount: Int { model.models.filter { model.labReports[$0.name] != nil }.count }

    var body: some View {
        @Bindable var model = model
        SettingsPageLayout(title: "Models") {
            SettingRow(title: "New conversations use", description: "Last Used picks the model you used most recently.") {
                Picker("New conversations use", selection: $model.chosenDefaultModel) {
                    Text("Last Used").tag("")
                    Divider()
                    ForEach(model.models) { Text(model.displayName($0.name)).tag($0.name) }
                }
                .labelsHidden()
                .fixedSize()
            }
            SettingRow(title: "Keep loaded for", description: "After its last reply. A loaded model answers at once but holds memory.", divider: false) {
                Picker("Keep loaded for", selection: $model.keepLoadedMinutes) {
                    ForEach([1, 5, 15, 30], id: \.self) { Text("^[\($0) minute](inflect: true)").tag($0) }
                }
                .labelsHidden()
                .fixedSize()
            }

            sectionHeader("On This Mac", detail: model.models.count == 1 ? "1 model" : "\(model.models.count) models") {
                if model.lab.isRunning {
                    Button("Stop Testing") { model.stop() }
                } else {
                    Button("Test All") { model.testAllModels() }
                        .disabled(model.isWriting || model.connection != .connected || model.models.isEmpty)
                        .help("Run the quick check on every model, one at a time. This can take a while.")
                }
            }
            if model.lab.isRunning {
                VStack(alignment: .leading, spacing: Space.xs) {
                    ProgressView(value: Double(model.lab.completed), total: Double(max(model.lab.total, 1)))
                    Text(model.labQueue.isEmpty
                         ? "Testing \(model.displayName(model.lab.modelName ?? ""))"
                         : "Testing \(model.displayName(model.lab.modelName ?? "")) · \(model.labQueue.count) more after this")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .padding(.bottom, Space.md)
            }
            ForEach(model.models) { item in
                ModelRow(item: item, isLast: item.id == model.models.last?.id, onRename: { renaming = item })
            }
            if model.models.isEmpty {
                Text("No models yet. Install one with Ollama, then it appears here.")
                    .foregroundStyle(.secondary)
                    .padding(.vertical, Space.lg)
            }

            if !winners.isEmpty {
                sectionHeader("Best For", detail: testedCount < model.models.count
                              ? "From \(testedCount) of \(model.models.count) models tested" : "From every model") { EmptyView() }
                Grid(alignment: .leading, horizontalSpacing: Space.xl, verticalSpacing: 0) {
                    ForEach(winners, id: \.area) { winner in
                        GridRow {
                            Label(winner.area.title, systemImage: winner.area.symbol)
                                .foregroundStyle(.secondary)
                            Text(model.displayName(winner.modelName))
                                .lineLimit(1)
                                .gridColumnAlignment(.leading)
                            Text(score(winner))
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                                .gridColumnAlignment(.trailing)
                        }
                        .frame(height: 36)
                        if winner.area != winners.last?.area {
                            Divider().gridCellColumns(3)
                        }
                    }
                }
            }
        }
        .tint(.secondary)
        .sheet(item: $renaming) { RenameModelSheet(item: $0) }
        .task { for item in model.models { model.loadLabReport(item.name) } }
    }

    private func sectionHeader<Trailing: View>(_ title: String, detail: String, @ViewBuilder trailing: () -> Trailing) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).font(.title3)
            Text(detail).foregroundStyle(.secondary)
            Spacer()
            trailing()
        }
        .padding(.top, Space.section)
        .padding(.bottom, Space.sm)
    }

    private func score(_ winner: LabLeaderboard.Winner) -> String {
        winner.area == .speed ? "\(Int(winner.tokensPerSecond.rounded())) tokens/s" : "\(winner.passed) of \(winner.total)"
    }
}

/// One model: aperture, name, what it can do, size, score, and its actions. Every row is the same height.
private struct ModelRow: View {
    let item: OllamaModel
    let isLast: Bool
    let onRename: () -> Void
    @Environment(AppModel.self) private var model

    private var report: LabReport? { model.labReports[item.name] }
    private var memory: Int64? { model.loaded.first { $0.name == item.name }?.memory }

    /// The second line: the original name when you've renamed it, and whether it's loaded.
    private var detail: String {
        var parts: [String] = []
        if model.modelNicknames[item.name] != nil { parts.append(item.name) }
        if let memory { parts.append("Loaded · \(ByteCountFormatter.string(fromByteCount: memory, countStyle: .file))") }
        return parts.isEmpty ? "Not loaded" : parts.joined(separator: " · ")
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: Space.lg) {
                Image(nsImage: ApertureIcon.image(memory != nil ? .open : .closed))
                    .foregroundStyle(memory != nil ? AnyShapeStyle(Palette.accentText) : AnyShapeStyle(.tertiary))
                    .help(memory != nil ? "In memory, ready to reply" : "Not in memory. It loads when you use it.")
                VStack(alignment: .leading, spacing: 2) {
                    Text(model.displayName(item.name)).lineLimit(1)
                    Text(detail)
                        .font(.callout)
                        .foregroundStyle(memory != nil ? AnyShapeStyle(Palette.accentText) : AnyShapeStyle(.secondary))
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                // Fixed columns, so models compare at a glance.
                HStack(spacing: Space.sm) {
                    ForEach(item.abilities, id: \.self) { title in
                        Image(systemName: Self.symbol(title)).help(title).accessibilityLabel(title)
                    }
                }
                .foregroundStyle(.secondary)
                .frame(width: 96, alignment: .leading)
                Text(ByteCountFormatter.string(fromByteCount: item.size, countStyle: .file))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .frame(width: 64, alignment: .trailing)
                Text(report.map { "\($0.totalPassed)/\($0.results.count)" } ?? "—")
                    .foregroundStyle(report == nil ? .tertiary : .primary)
                    .monospacedDigit()
                    .frame(width: 48, alignment: .trailing)
                    .help(report == nil ? "Not tested yet" : "Tests passed in the last run")
                Button(report == nil ? "Test" : "Results") { model.openLab(item.name) }
                    .frame(width: 72)
                Menu {
                    Button("Rename…", action: onRename)
                    if memory != nil {
                        Button("Unload") { Task { await model.unload(item.name) } }
                            .disabled(!model.canUnload(item.name))
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .foregroundStyle(.secondary)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .help("More actions for this model")
                .accessibilityLabel("More actions for \(model.displayName(item.name))")
            }
            .frame(height: 56)
            if !isLast { Divider() }
        }
        .contextMenu {
            Button("Rename…", action: onRename)
            Button(report == nil ? "Test" : "See Results") { model.openLab(item.name) }
            if memory != nil { Button("Unload") { Task { await model.unload(item.name) } } }
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
