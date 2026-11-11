import SwiftUI
import LanternKit

/// The greeting on a new conversation: the mark and a line in the app's serif, by time of day,
/// with your first name from your Mac account. Nothing leaves this Mac.
struct WelcomeView: View {
    var body: some View {
        HStack(spacing: Space.md) {
            BrandMark()
                .frame(width: 36, height: 36)
            Text(greeting)
                .font(.system(size: 34, weight: .regular, design: .serif)) // grid: ok display type
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    private var greeting: String {
        let time = switch Calendar.current.component(.hour, from: .now) {
        case 5..<12: "Good morning"
        case 12..<17: "Good afternoon"
        case 17..<22: "Good evening"
        default: "Up late"
        }
        // The profile's own name, which starts as this Mac account's first name.
        let first = ProfileStore.shared.current.name.split(separator: " ").first.map(String.init) ?? ""
        return first.isEmpty ? time : "\(time), \(first)"
    }
}

/// A few ways to start, under the message box. Each fills the box; the file ones also open the file picker.
struct StarterRow: View {
    @Environment(AppModel.self) private var model

    private struct Starter: Identifiable {
        let title: String
        let symbol: String
        let prompt: String
        var attaches = false
        var id: String { title }
    }

    private var current: OllamaModel? { model.models.first { $0.name == model.currentModelName } }

    private var starters: [Starter] {
        var list: [Starter] = []
        if current?.supportsAudio == true {
            list.append(Starter(title: "Transcribe", symbol: "waveform", prompt: "Transcribe this recording.", attaches: true))
        }
        list.append(Starter(title: "Summarize", symbol: "doc.text", prompt: "Summarize this in five short points.", attaches: true))
        if current?.supportsImages == true {
            list.append(Starter(title: "Describe Image", symbol: "photo", prompt: "What's in this image?", attaches: true))
        }
        list.append(Starter(title: "Explain Code", symbol: "chevron.left.forwardslash.chevron.right", prompt: "Explain what this code does:\n\n"))
        list.append(Starter(title: "Write", symbol: "pencil.line", prompt: "Help me write "))
        return list
    }

    var body: some View {
        HStack(spacing: Space.sm) {
            ForEach(starters) { starter in
                Button {
                    model.prefill = starter.prompt
                    if starter.attaches { model.chooseFiles() }
                } label: {
                    Label(starter.title, systemImage: starter.symbol)
                        .font(.callout)
                        .padding(.horizontal, Space.md)
                        .padding(.vertical, Space.sm)
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .background(.fill.quaternary, in: Capsule())
                .overlay(Capsule().strokeBorder(.separator))
                .help(starter.attaches ? "Fill in the message, then choose a file" : "Fill in the message")
            }
        }
        .disabled(model.currentModelName == nil || model.connection != .connected)
        .padding(.horizontal, Space.margin)
    }
}
