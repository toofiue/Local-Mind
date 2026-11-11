import SwiftUI
import LanternKit

extension LabArea {
    var symbol: String {
        switch self {
        case .speed: "gauge.with.dots.needle.67percent"
        case .reasoning: "function"
        case .code: "chevron.left.forwardslash.chevron.right"
        case .instructions: "list.bullet.clipboard"
        case .data: "tablecells"
        case .documents: "doc.text"
        case .images: "photo"
        case .audio: "waveform"
        case .tools: "wrench.and.screwdriver"
        }
    }
}

/// Gives a model a name of your own.
struct RenameModelSheet: View {
    let item: OllamaModel
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: Space.lg) {
            Text("Name This Model")
                .font(TextStyle.heading)
            TextField("Name", text: $name, prompt: Text(item.name))
                .focused($isFocused)
                .onSubmit(save)
            Text("Shown in your conversations and Quick Ask. The original name, \(item.name), stays in the model list.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                if model.modelNicknames[item.name] != nil {
                    Button("Use Original") {
                        model.setNickname("", for: item.name)
                        dismiss()
                    }
                }
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Save", action: save)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(Space.margin)
        .frame(width: Layout.renameSheet)
        .onAppear {
            name = model.modelNicknames[item.name] ?? ""
            isFocused = true
        }
    }

    private func save() {
        model.setNickname(name, for: item.name)
        dismiss()
    }
}
