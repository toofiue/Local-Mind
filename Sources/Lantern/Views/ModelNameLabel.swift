import SwiftUI

/// A model's name, with the original in small text below it if you've renamed it.
struct ModelNameLabel: View {
    let name: String
    /// Smaller text, so two lines fit inside a toolbar button.
    var isCompact = false
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if isCompact && model.modelNicknames[name] != nil {
                Text(model.displayName(name)).font(.caption).fontWeight(.medium)
            } else {
                Text(model.displayName(name))
            }
            if model.modelNicknames[name] != nil {
                Text(name)
                    .font(isCompact ? .system(.caption2).leading(.tight) : .caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
