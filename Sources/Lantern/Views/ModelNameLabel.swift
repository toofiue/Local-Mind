import SwiftUI

/// A model's name, with the original in small text below it if you've renamed it.
/// For places where you're choosing between models. Elsewhere only your name shows.
struct ModelNameLabel: View {
    let name: String
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(model.displayName(name))
            if model.modelNicknames[name] != nil {
                Text(name)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
