import SwiftUI
import LanternKit

/// Tests one model, and explains what was tested and how it went.
struct ModelLabPage: View {
    let name: String
    @Environment(AppModel.self) private var model

    private var isRunningHere: Bool { model.lab.modelName == name }
    private var installed: OllamaModel? { model.models.first { $0.name == name } }
    private var report: LabReport? { model.labReports[name] }

    /// The areas this model can be tested in.
    private var areas: [LabArea] {
        guard let installed else { return LabArea.allCases }
        let tested = Set(ModelLab.cases(for: installed).map(\.area))
        return LabArea.allCases.filter(tested.contains)
    }

    var body: some View {
        @Bindable var model = model
        Form {
            Section {
                Picker("View", selection: $model.labTab) {
                    ForEach(LabTab.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }

            switch model.labTab {
            case .quickCheck: quickCheck
            case .benchmark: BenchmarkSections(name: name)
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .background(Palette.canvas)
        .navigationTitle(model.displayName(name))
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button("Models", systemImage: "chevron.left") { model.closeLab() }
                    .help("Back to all models")
            }
        }
        .task {
            model.loadLabReport(name)
            model.loadBenchmarkReport(name)
        }
    }

    @ViewBuilder
    private var quickCheck: some View {
        Section { header }

        if let warning = model.memoryWarning, warning.surface == .lab {
            Section {
                MemoryWarningView(warning: warning, actionTitle: "Run Anyway") {
                    model.runLab(name, skipMemoryCheck: true)
                }
            }
        }

        if isRunningHere {
            Section("Testing") { progress }
        } else if let report {
            LabResults(report: report)
        } else {
            Section("What Gets Tested") {
                ForEach(areas) { LabAreaIntro(area: $0) }
            }
        }

        Section {
            Text("A few tests per area, modeled on published benchmarks, so these scores can't be compared with their published numbers. For that, use Full Benchmark.")
                .font(.callout)
                .foregroundStyle(.secondary)
        } header: {
            Text("About These Tests")
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: Space.lg) {
            VStack(alignment: .leading, spacing: Space.xs) {
                if let report, !isRunningHere {
                    Text("\(report.totalPassed) of \(report.results.count)")
                        .font(.largeTitle.weight(.semibold))
                        .monospacedDigit()
                    Text("tests passed · \(report.date, format: .dateTime.day().month().hour().minute())")
                        .foregroundStyle(.secondary)
                } else {
                    Text(installed.map { "\(ModelLab.cases(for: $0).count) tests across \(areas.count) areas" } ?? "Model Test")
                        .font(.title3.weight(.semibold))
                    Text("Takes a few minutes and uses this model's full memory.")
                        .foregroundStyle(.secondary)
                }
                Text(macSummary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: Space.lg)
            if isRunningHere {
                Button("Stop") { model.lab.stop() }
            } else {
                Button(report == nil ? "Run Quick Check" : "Run Again") { model.runLab(name) }
                    .buttonStyle(.borderedProminent)
                    .disabled(model.isWriting || model.connection != .connected)
            }
        }
        .padding(.vertical, Space.xs)
    }

    private var macSummary: String {
        let memory = model.readMemory()
        let total = ByteCountFormatter.string(fromByteCount: memory.totalBytes, countStyle: .memory)
        let free = ByteCountFormatter.string(fromByteCount: memory.availableBytes, countStyle: .memory)
        let size = installed.map { ByteCountFormatter.string(fromByteCount: MemoryAdvisor.estimatedNeed(modelSize: $0.size), countStyle: .file) } ?? "?"
        return "\(SystemMonitor.chipName) · \(total) memory, \(free) free · needs about \(size)"
    }

    private var progress: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            ProgressView(value: Double(model.lab.completed), total: Double(max(model.lab.total, 1)))
            Text("\(model.lab.currentTest) · \(model.lab.completed + 1) of \(model.lab.total)")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }
}

private struct LabAreaIntro: View {
    let area: LabArea

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            Text(area.title)
                .font(.headline)
            Text(area.measures)
            if let standard = area.standard {
                Text("Based on \(standard.name)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("No published standard applied")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, Space.xs)
    }
}

private struct LabResults: View {
    let report: LabReport

    var body: some View {
        if !report.goodFor.isEmpty {
            Section("Good For") {
                ForEach(report.goodFor, id: \.self) { Label($0, systemImage: "checkmark.circle") }
            }
        }
        if !report.limits.isEmpty {
            Section("Limits") {
                ForEach(report.limits, id: \.self) { Label($0, systemImage: "exclamationmark.triangle") }
            }
        }
        ForEach(LabArea.allCases) { area in
            if !report.results(in: area).isEmpty {
                LabAreaSection(area: area, report: report)
            }
        }
    }
}

private struct LabAreaSection: View {
    let area: LabArea
    let report: LabReport

    var body: some View {
        Section {
            VStack(alignment: .leading, spacing: Space.sm) {
                Text(area.measures)
                Text(area.scoring)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                if let standard = area.standard {
                    HStack(alignment: .firstTextBaseline, spacing: Space.xs) {
                        Link(standard.name, destination: standard.url)
                            .font(.callout)
                        Text(standard.relation)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Text("No published standard applied. This is a basic check that the model can see.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, Space.xs)

            if area == .speed {
                LabeledContent("Writing speed", value: "\(Int(report.tokensPerSecond.rounded())) tokens per second")
                LabeledContent("Load time", value: "\(Int(report.loadSeconds.rounded())) seconds")
                LabeledContent("Memory used", value: memoryUsed)
            }

            ForEach(report.results(in: area)) { LabTestRow(result: $0) }
        } header: {
            HStack {
                Text(area.title)
                Spacer()
                if area != .speed {
                    Text("\(report.passed(in: area)) of \(report.results(in: area).count)")
                        .monospacedDigit()
                }
                if let rating = report.rating(in: area) {
                    Text(rating.rawValue)
                        .font(.caption)
                        .padding(.horizontal, Space.sm)
                        .padding(.vertical, 2)
                        .background(.fill.tertiary, in: Capsule())
                }
            }
        }
    }

    private var memoryUsed: String {
        let used = ByteCountFormatter.string(fromByteCount: report.memoryBytes, countStyle: .file)
        guard report.totalMemoryBytes > 0 else { return used }
        return "\(used), \(Int(Double(report.memoryBytes) / Double(report.totalMemoryBytes) * 100))% of this Mac"
    }
}

/// One test: passed or failed, and on opening it, exactly what happened.
private struct LabTestRow: View {
    let result: LabCaseResult

    var body: some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: Space.sm) {
                if let prompt = result.prompt { detail("Asked", prompt) }
                if let expected = result.expected { detail("Expected", expected) }
                detail("Model replied", result.reply.isEmpty ? "No reply" : result.reply)
            }
            .padding(.vertical, Space.xs)
        } label: {
            HStack {
                Label(result.name, systemImage: result.passed ? "checkmark.circle.fill" : "xmark.circle")
                Spacer()
                Text(result.passed ? "Passed" : "Failed")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func detail(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.callout)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
