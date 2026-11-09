import SwiftUI
import LanternKit

/// Tests one model and shows what it's good for.
struct ModelLabPage: View {
    let name: String
    @Environment(AppModel.self) private var model

    private var isRunningHere: Bool { model.lab.modelName == name }
    private var installed: OllamaModel? { model.models.first { $0.name == name } }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.xxl) {
                header
                if let warning = model.memoryWarning, warning.surface == .lab {
                    MemoryWarningView(warning: warning, actionTitle: "Run Anyway") {
                        model.runLab(name, skipMemoryCheck: true)
                    }
                }
                if isRunningHere {
                    progress
                } else if let report = model.labReports[name] {
                    LabReportView(report: report)
                } else {
                    Text("Tests speed, reasoning, coding, following instructions, structured data, long documents, images, and tools. It takes a few minutes and uses this model's full memory.")
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: Layout.column, alignment: .leading)
            .padding(Space.margin)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle(model.displayName(name))
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button("Models", systemImage: "chevron.left") { model.closeLab() }
                    .help("Back to all models")
            }
        }
        .task { model.loadLabReport(name) }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: Space.lg) {
            VStack(alignment: .leading, spacing: Space.xs) {
                ModelNameLabel(name: name)
                    .font(.title3)
                Text(macSummary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: Space.lg)
            if isRunningHere {
                Button("Stop") { model.lab.stop() }
            } else {
                Button(model.labReports[name] == nil ? "Run Test" : "Run Again") { model.runLab(name) }
                    .buttonStyle(.borderedProminent)
                    .disabled(model.isWriting || model.connection != .connected)
            }
        }
    }

    private var macSummary: String {
        let memory = model.readMemory()
        let total = ByteCountFormatter.string(fromByteCount: memory.totalBytes, countStyle: .memory)
        let free = ByteCountFormatter.string(fromByteCount: memory.availableBytes, countStyle: .memory)
        let size = installed.map { ByteCountFormatter.string(fromByteCount: MemoryAdvisor.estimatedNeed(modelSize: $0.size), countStyle: .file) } ?? "?"
        return "\(SystemMonitor.chipName) · \(total) memory, \(free) free · This model needs about \(size)"
    }

    private var progress: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            ProgressView(value: Double(model.lab.completed), total: Double(max(model.lab.total, 1)))
            Text("\(model.lab.currentTest) (\(model.lab.completed + 1) of \(model.lab.total))")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }
}

private struct LabReportView: View {
    let report: LabReport

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xxl) {
            if !report.goodFor.isEmpty {
                section("Good For", items: report.goodFor, symbol: "checkmark.circle")
            }
            if !report.limits.isEmpty {
                section("Limits", items: report.limits, symbol: "exclamationmark.triangle")
            }
            VStack(alignment: .leading, spacing: Space.sm) {
                Text("Results")
                    .font(.headline)
                ForEach(LabArea.allCases) { area in
                    if !report.results(in: area).isEmpty {
                        AreaRow(area: area, report: report)
                    }
                }
            }
            Text("Tested \(report.date, format: .dateTime.day().month().hour().minute())")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func section(_ title: String, items: [String], symbol: String) -> some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            Text(title)
                .font(.headline)
            ForEach(items, id: \.self) { item in
                Label(item, systemImage: symbol)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct AreaRow: View {
    let area: LabArea
    let report: LabReport

    private var summary: String {
        let results = report.results(in: area)
        if area == .speed {
            let memory = ByteCountFormatter.string(fromByteCount: report.memoryBytes, countStyle: .file)
            return "\(Int(report.tokensPerSecond.rounded())) tokens per second · loads in \(Int(report.loadSeconds.rounded())) s · uses \(memory)"
        }
        return "\(report.passed(in: area)) of \(results.count)"
    }

    var body: some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: Space.sm) {
                ForEach(report.results(in: area)) { result in
                    HStack(alignment: .firstTextBaseline, spacing: Space.sm) {
                        Image(systemName: result.passed ? "checkmark" : "xmark")
                            .foregroundStyle(.secondary)
                            .accessibilityLabel(result.passed ? "Passed" : "Failed")
                        VStack(alignment: .leading, spacing: 0) {
                            Text(result.name)
                            Text(result.reply)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(3)
                                .textSelection(.enabled)
                        }
                    }
                }
            }
            .padding(.top, Space.xs)
        } label: {
            HStack {
                Text(area.title)
                Spacer(minLength: Space.md)
                Text(summary)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
    }
}
