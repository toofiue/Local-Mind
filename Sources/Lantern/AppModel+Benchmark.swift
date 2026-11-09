import Foundation
import SwiftData
import LanternKit

extension AppModel {
    var benchmarksAreDownloaded: Bool {
        BenchmarkSuite.allCases.allSatisfy(benchmarkLibrary.isDownloaded)
    }

    /// Fetches the published test sets, checking each against its known checksum.
    func downloadBenchmarks() async {
        benchmarkDownloadFailed = false
        isDownloadingBenchmarks = true
        defer { isDownloadingBenchmarks = false }
        do {
            for suite in BenchmarkSuite.allCases where !benchmarkLibrary.isDownloaded(suite) {
                try await benchmarkLibrary.download(suite)
            }
        } catch {
            benchmarkDownloadFailed = true
        }
    }

    func benchmarkSuites(includingCode: Bool) -> [BenchmarkSuite] {
        BenchmarkSuite.allCases.filter { $0 != .humaneval || (includingCode && CodeSandbox.isAvailable) }
    }

    func runBenchmark(_ modelName: String, size: BenchmarkSize, includingCode: Bool, skipMemoryCheck: Bool = false) {
        guard !isWriting, connection == .connected,
              let installed = models.first(where: { $0.name == modelName }) else { return }
        if !skipMemoryCheck, let warning = memoryWarningIfNeeded(for: modelName, surface: .benchmark) {
            memoryWarning = warning
            return
        }
        memoryWarning = nil
        let plan = benchmarkSuites(includingCode: includingCode).map { suite in
            (suite: suite, items: BenchmarkLoader.sample(benchmarkLibrary.items(suite), count: size.count(for: suite)))
        }.filter { !$0.items.isEmpty }
        guard !plan.isEmpty else { return }
        benchmark.start(installed, plan: plan, size: size, client: client)
    }

    func saveBenchmarkReport(_ report: BenchmarkReport) {
        guard let payload = try? JSONEncoder().encode(report) else { return }
        context.insert(BenchmarkRun(modelName: report.modelName, date: report.date, payload: payload))
        try? context.save()
        benchmarkReports[report.modelName] = report
    }

    func loadBenchmarkReport(_ modelName: String) {
        var descriptor = FetchDescriptor<BenchmarkRun>(predicate: #Predicate { $0.modelName == modelName },
                                                       sortBy: [SortDescriptor(\.date, order: .reverse)])
        descriptor.fetchLimit = 1
        guard let run = try? context.fetch(descriptor).first,
              let report = try? JSONDecoder().decode(BenchmarkReport.self, from: run.payload) else { return }
        benchmarkReports[modelName] = report
    }
}

enum LabTab: String, CaseIterable, Identifiable {
    case quickCheck = "Quick Check", benchmark = "Full Benchmark"

    var id: String { rawValue }
}
