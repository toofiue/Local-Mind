import SwiftUI

/// One line saying a model won't fit comfortably, with a way to go ahead.
/// Sending again checks again, so there's no separate button for that.
struct MemoryWarningView: View {
    let warning: MemoryWarning
    var actionTitle = "Send Anyway"
    let onContinue: () -> Void

    var body: some View {
        HStack(spacing: Space.md) {
            Label(warning.message, systemImage: "memorychip")
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            Spacer(minLength: Space.sm)
            Button(actionTitle, action: onContinue)
                .controlSize(.small)
        }
        .help(warning.appsSummary.isEmpty ? "Closing other apps frees memory." : "\(warning.appsSummary). Closing them frees memory.")
    }
}
