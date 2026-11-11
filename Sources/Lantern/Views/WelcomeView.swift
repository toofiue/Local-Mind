import SwiftUI
import LanternKit

/// What a new conversation shows before the first message: who is here, whether
/// it's ready, and a few ways to start that suit what this model can do.
struct WelcomeView: View {
    @Environment(AppModel.self) private var model

    private var current: OllamaModel? { model.models.first { $0.name == model.currentModelName } }

    var body: some View {
        VStack(spacing: Space.xl) {
            BrandMark()
                .frame(width: 56, height: 56)
            VStack(spacing: Space.sm) {
                Text(greeting)
                    .font(.system(.largeTitle, design: .serif))
                    .foregroundStyle(.primary)
                status
            }
            starters
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: Layout.column)
        .padding(.horizontal, Space.margin)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var greeting: String {
        switch Calendar.current.component(.hour, from: .now) {
        case 5..<12: "Good morning"
        case 12..<17: "Good afternoon"
        default: "Good evening"
        }
    }

    @ViewBuilder private var status: some View {
        if let name = model.currentModelName {
            let ready = model.loaded.contains { $0.name == name }
            HStack(spacing: Space.xs) {
                Image(nsImage: ApertureIcon.image(ready ? .open : .closed))
                    .foregroundStyle(ready ? AnyShapeStyle(Palette.accentText) : AnyShapeStyle(.secondary))
                    .accessibilityHidden(true)
                Text(ready ? "\(model.displayName(name)) is ready" : "\(model.displayName(name)) wakes up when you send")
                Text("·")
                Text("Private to this Mac")
            }
            .font(.callout)
            .foregroundStyle(.secondary)
        }
    }

    private var starters: some View {
        HStack(spacing: Space.sm) {
            ForEach(startersForModel, id: \.title) { starter in
                Button {
                    model.prefill = starter.prompt
                    if starter.attaches { model.chooseFiles() }
                } label: {
                    Label(starter.title, systemImage: starter.symbol)
                        .font(.callout)
                        .padding(.horizontal, Space.md)
                        .padding(.vertical, Space.sm)
                        .background(.fill.quaternary, in: Capsule())
                        .overlay(Capsule().strokeBorder(.separator))
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .help(starter.attaches ? "Choose a file, then send" : "Start with this message")
            }
        }
        .disabled(model.currentModelName == nil)
    }

    private struct Starter {
        let title: String
        let symbol: String
        let prompt: String
        var attaches = false
    }

    private var startersForModel: [Starter] {
        var list: [Starter] = []
        if current?.supportsAudio == true {
            list.append(Starter(title: "Transcribe a recording", symbol: "waveform", prompt: "Transcribe this recording.", attaches: true))
        }
        list.append(Starter(title: "Summarize a document", symbol: "doc.text", prompt: "Summarize this in five short points.", attaches: true))
        if current?.supportsImages == true {
            list.append(Starter(title: "Describe an image", symbol: "photo", prompt: "What's in this image?", attaches: true))
        }
        list.append(Starter(title: "Draft an email", symbol: "envelope", prompt: "Draft a short, friendly email that "))
        return Array(list.prefix(3))
    }
}
