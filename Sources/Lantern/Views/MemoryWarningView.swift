import SwiftUI

/// Says a model won't fit comfortably, and what to do about it.
struct MemoryWarningView: View {
    let warning: MemoryWarning
    var actionTitle = "Send Anyway"
    let onContinue: () -> Void
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            Label(warning.message, systemImage: "memorychip")
                .font(.callout)
                .foregroundStyle(.secondary)
            if !warning.appsSummary.isEmpty {
                Text(warning.appsSummary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: Space.sm) {
                Button("Check Again") { model.recheckMemory() }
                Button(actionTitle, action: onContinue)
            }
        }
    }
}
