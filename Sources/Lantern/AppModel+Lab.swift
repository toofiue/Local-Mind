import Foundation
import SwiftData
import LanternKit

extension AppModel {
    func openLab(_ modelName: String) {
        memoryWarning = nil
        selection = nil
        showingModels = false
        labTab = .quickCheck
        labModelName = modelName
    }

    func closeLab() {
        memoryWarning = nil
        labModelName = nil
        showingModels = true
    }

    /// Runs the tests, unless the model won't fit and you haven't said to go ahead.
    func runLab(_ modelName: String, skipMemoryCheck: Bool = false) {
        guard !isWriting, connection == .connected,
              let installed = models.first(where: { $0.name == modelName }) else { return }
        if !skipMemoryCheck, let warning = memoryWarningIfNeeded(for: modelName, surface: .lab) {
            memoryWarning = warning
            return
        }
        memoryWarning = nil
        lab.start(installed, client: client, totalMemory: readMemory().totalBytes, swapUsed: { SystemMonitor.swapUsedBytes() })
    }

    /// Runs the quick check on every model, one after another, smallest first.
    func testAllModels() {
        guard !isWriting, connection == .connected else { return }
        let order = models.sorted { $0.size < $1.size }.map(\.name)
        guard let first = order.first else { return }
        labQueue = Array(order.dropFirst())
        runLab(first, skipMemoryCheck: true)
    }

    func saveLabReport(_ report: LabReport) {
        guard let payload = try? JSONEncoder().encode(report) else { return }
        context.insert(ModelTestRun(modelName: report.modelName, date: report.date, payload: payload))
        try? context.save()
        labReports[report.modelName] = report
    }

    /// Reads the most recent saved run for a model.
    func loadLabReport(_ modelName: String) {
        var descriptor = FetchDescriptor<ModelTestRun>(predicate: #Predicate { $0.modelName == modelName },
                                                       sortBy: [SortDescriptor(\.date, order: .reverse)])
        descriptor.fetchLimit = 1
        guard let run = try? context.fetch(descriptor).first,
              let report = try? JSONDecoder().decode(LabReport.self, from: run.payload) else { return }
        labReports[modelName] = report
    }
}
