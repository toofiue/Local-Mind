import SwiftUI
import LanternKit

/// The Full Benchmark: the real published test sets, run on this model.
struct BenchmarkSections: View {
    let name: String
    @Environment(AppModel.self) private var model
    @AppStorage("benchmarkSize") private var size = BenchmarkSize.sample50
    @AppStorage("benchmarkIncludesCode") private var includesCode = false

    private var isRunningHere: Bool { model.benchmark.modelName == name }
    private var report: BenchmarkReport? { model.benchmarkReports[name] }

    private var downloadSize: String {
        let total = BenchmarkSuite.allCases.reduce(0) { $0 + $1.downloadBytes }
        return ByteCountFormatter.string(fromByteCount: total, countStyle: .file)
    }

    private var chosenSuites: [BenchmarkSuite] { model.benchmarkSuites(includingCode: includesCode) }

    private var estimate: String? {
        guard let speed = model.labReports[name]?.tokensPerSecond, speed > 0 else { return nil }
        let minutes = BenchmarkEstimate.minutes(size: size, suites: chosenSuites, tokensPerSecond: speed)
        if minutes < 60 { return "About \(minutes) minutes at this model's speed." }
        return "About \(minutes / 60) hours \(minutes % 60) minutes at this model's speed. Keep your Mac plugged in."
    }

    var body: some View {
        Section {
            Text("Runs the actual published question sets and scores them the published way. Replies are generated without visible thinking, and published scores vary with how a test is run.")
                .fixedSize(horizontal: false, vertical: true)

            ForEach(BenchmarkSuite.allCases) { SuiteRow(suite: $0) }

            if !model.benchmarksAreDownloaded {
                HStack {
                    Text(model.benchmarkDownloadFailed ? "Unable to download the test sets. Check your connection and try again." : "The test sets are \(downloadSize), downloaded once from their official sources.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Spacer(minLength: Space.md)
                    Button(model.isDownloadingBenchmarks ? "Downloading…" : "Download") {
                        Task { await model.downloadBenchmarks() }
                    }
                    .disabled(model.isDownloadingBenchmarks)
                }
            } else {
                Picker("Questions", selection: $size) {
                    ForEach(BenchmarkSize.allCases) { Text($0.title).tag($0) }
                }
                Toggle(isOn: $includesCode) {
                    VStack(alignment: .leading, spacing: Space.xs) {
                        Text("Include HumanEval")
                        Text("Runs code the model wrote, in a sandbox with no network, no file writes, and no access to your files.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .disabled(!CodeSandbox.isAvailable)
                if let warning = model.memoryWarning, warning.surface == .benchmark {
                    MemoryWarningView(warning: warning, actionTitle: "Run Anyway") { run(skipMemoryCheck: true) }
                }
                if isRunningHere {
                    runningRow
                } else {
                    HStack {
                        if let estimate {
                            Text(estimate)
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: Space.md)
                        Button("Run Benchmark") { run(skipMemoryCheck: false) }
                            .disabled(model.isWriting || model.connection != .connected)
                    }
                }
            }
        } header: {
            Text("Full Benchmark")
        }

        if let report, !isRunningHere {
            ForEach(report.suites) { BenchmarkResultSection(result: $0, report: report) }
        }
    }

    private func run(skipMemoryCheck: Bool) {
        model.runBenchmark(name, size: size, includingCode: includesCode, skipMemoryCheck: skipMemoryCheck)
    }

    private var runningRow: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            ProgressView(value: Double(model.benchmark.completed), total: Double(max(model.benchmark.total, 1)))
            HStack {
                Text("\(model.benchmark.currentSuite?.title ?? "Starting") · \(model.benchmark.completed) of \(model.benchmark.total)")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Stop") { model.benchmark.stop() }
            }
        }
    }
}

private struct SuiteRow: View {
    let suite: BenchmarkSuite

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            HStack(spacing: Space.xs) {
                Link(suite.title, destination: suite.infoURL)
                    .font(.headline)
                Text("\(suite.itemCount.formatted()) questions · \(suite.license) license")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text(suite.measures)
            Text(suite.scoring)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, Space.xs)
    }
}

private struct BenchmarkResultSection: View {
    let result: BenchmarkSuiteResult
    let report: BenchmarkReport

    private var failures: [BenchmarkItemResult] { result.items.filter { !$0.passed } }

    private var percent: String { "\(Int((result.share * 100).rounded()))%" }

    private var note: String {
        if result.isComplete { return "The complete published set, so this can be compared with published scores run the same way." }
        let margin = Int((result.marginOfError * 100).rounded())
        return "\(result.items.count) of \(result.suite.itemCount.formatted()) questions. The whole set's score is likely within \(margin) points of this. Compare it with other models here, not with published scores."
    }

    var body: some View {
        Section {
            VStack(alignment: .leading, spacing: Space.sm) {
                HStack(alignment: .firstTextBaseline) {
                    Text(percent)
                        .font(.largeTitle.weight(.semibold))
                        .monospacedDigit()
                    Text("\(result.passed) of \(result.items.count) passed")
                        .foregroundStyle(.secondary)
                }
                ProgressView(value: result.share)
                Text(note)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if report.wasStopped {
                    Text("This run was stopped early.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, Space.xs)

            if !failures.isEmpty {
                DisclosureGroup("Failed Questions") {
                    ForEach(failures.prefix(30)) { BenchmarkFailureRow(item: $0) }
                    if failures.count > 30 {
                        Text("And \(failures.count - 30) more.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        } header: {
            Text(result.suite.title)
        }
    }
}

private struct BenchmarkFailureRow: View {
    let item: BenchmarkItemResult

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            Text(item.id)
                .font(.callout)
            if let detail = item.detail {
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text(item.reply.isEmpty ? "No reply" : item.reply)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(4)
                .textSelection(.enabled)
        }
        .padding(.vertical, Space.xs)
    }
}
