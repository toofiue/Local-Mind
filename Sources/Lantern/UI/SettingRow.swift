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
