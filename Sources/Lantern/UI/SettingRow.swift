import SwiftUI

/// One setting: the name and a short description on the left,
/// the control on the right, and a thin line under it. Regular weight throughout.
struct SettingRow<Control: View>: View {
    let title: String
    var description: String?
    var divider = true
    @ViewBuilder var control: Control

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: Space.xl) {
                VStack(alignment: .leading, spacing: Space.xs) {
                    Text(title)
                    if let description {
                        Text(description)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                control
            }
            .padding(.vertical, Space.lg)
            if divider { Divider() }
        }
        .accessibilityElement(children: .contain)
    }
}

/// A page of settings: a title, then rows.
struct SettingsPageLayout<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text(title)
                    .font(.title3)
                    .padding(.bottom, Space.sm)
                content
            }
            .padding(.horizontal, Space.xxl)
            .padding(.vertical, Space.xl)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// Plain buttons in Settings: neutral gray, so the accent stays for what's selected.
struct SettingsButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, Space.md)
            .frame(minHeight: 28)
            .background(configuration.isPressed ? AnyShapeStyle(.fill.secondary) : AnyShapeStyle(.fill.tertiary),
                        in: RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            .foregroundStyle(isEnabled ? .primary : .tertiary)
            .contentShape(Rectangle())
    }
}
