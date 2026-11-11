import SwiftUI

/// Settings > Appearance: the accent color. Light and dark mode follow the Mac.
struct AppearanceSettings: View {
    @Bindable private var store = ThemeStore.shared

    var body: some View {
        Section {
            AccentPreview()
                .padding(.vertical, Space.xs)
            LabeledContent("Accent color") {
                VStack(alignment: .trailing, spacing: Space.xs) {
                    HStack(spacing: Space.sm) {
                        ForEach(Theme.all) { theme in
                            AccentSwatch(theme: theme, selected: store.themeID == theme.id) {
                                store.themeID = theme.id
                            }
                        }
                    }
                    Text(store.theme.name)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

/// A small Local Mind window in the chosen accent: conversations, a question,
/// a reply, and the message field. It redraws as people pick a color.
private struct AccentPreview: View {
    private let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Divider()
            chat
        }
        .frame(height: 188)
        .background(.background, in: shape)
        .clipShape(shape)
        .overlay(shape.strokeBorder(.separator, lineWidth: 1))
        .allowsHitTesting(false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Preview of the accent color")
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            HStack(spacing: Space.xs) {
                ForEach(0..<3, id: \.self) { _ in
                    Circle().fill(.quaternary).frame(width: 8, height: 8)
                }
            }
            .padding(.leading, Space.xs)
            .padding(.bottom, Space.sm)
            row("Weekend in Lisbon", selected: true)
            row("Summarize the report", selected: false)
            row("Voice note", selected: false)
            Spacer(minLength: 0)
            Label("Models", systemImage: "cpu")
                .font(.caption)
                .foregroundStyle(Palette.accentText)
                .padding(.leading, Space.xs)
        }
        .padding(Space.sm)
        .frame(width: 148)
        .background(.background.secondary)
    }

    private func row(_ title: String, selected: Bool) -> some View {
        Text(title)
            .font(.caption)
            .lineLimit(1)
            .foregroundStyle(selected ? Palette.onAccent : .primary)
            .padding(.horizontal, Space.sm)
            .frame(maxWidth: .infinity, minHeight: 24, alignment: .leading)
            .background(selected ? Palette.accent : .clear,
                        in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    // Drawn, not real controls: the preview is a picture, and real
    // controls turn gray when the window is not in front.
    private var chat: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            HStack {
                Spacer()
                Text("Plan a slow weekend in Lisbon")
                    .font(.caption)
                    .padding(.horizontal, Space.sm)
                    .padding(.vertical, Space.xs)
                    .background(.fill.tertiary, in: Capsule())
            }
            HStack(spacing: Space.xs) {
                BrandMark().frame(width: 12, height: 12)
                Text("gemma4").font(.caption2.weight(.medium)).foregroundStyle(.secondary)
            }
            Text("Saturday: coffee in Alfama, then the tram up to the castle. Sunday: Belém, pastries, and the river at sunset.")
                .font(.caption)
                .lineLimit(3)
            Spacer(minLength: 0)
            HStack {
                Text("Ask anything").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Image(systemName: "arrow.up")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(Palette.onAccent)
                    .frame(width: 20, height: 20)
                    .background(Palette.accent, in: Circle())
            }
            .padding(.leading, Space.sm)
            .padding(Space.xs)
            .background(.fill.quaternary, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .padding(Space.md)
    }
}

/// One color dot, like the accent row in System Settings.
private struct AccentSwatch: View {
    let theme: Theme
    let selected: Bool
    let choose: () -> Void

    var body: some View {
        Button(action: choose) {
            Circle()
                .fill(fill)
                .frame(width: 16, height: 16)
                .overlay {
                    if selected {
                        Circle().fill(theme.onAccent).frame(width: 6, height: 6) // grid: ok
                    }
                }
                .overlay(Circle().strokeBorder(.primary.opacity(0.15), lineWidth: 1))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(theme.name)
        .accessibilityLabel(theme.name)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var fill: AnyShapeStyle {
        if let tint = theme.tint {
            AnyShapeStyle(tint)
        } else {
            AnyShapeStyle(AngularGradient(colors: [.red, .orange, .yellow, .green, .blue, .purple, .pink, .red],
                                          center: .center))
        }
    }
}
