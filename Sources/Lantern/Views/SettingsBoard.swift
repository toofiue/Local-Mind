import SwiftUI

/// Settings inside the main window: a board in the middle over a dimmed window,
/// with sections on the left and their settings on the right. It has a largest size and shrinks
/// with a small window, keeping a margin all round. Escape, the close button, or a click outside closes it.
struct SettingsBoard: View {
    @Environment(AppModel.self) private var model
    @State private var section: BoardSection = .profile

    enum BoardSection: String, CaseIterable, Identifiable {
        case profile, appearance, models, quickAsk
        var id: String { rawValue }
        var title: String {
            switch self {
            case .profile: "Profile"
            case .appearance: "Appearance"
            case .models: "Models"
            case .quickAsk: "Quick Ask"
            }
        }
        var symbol: String {
            switch self {
            case .profile: "person.crop.circle"
            case .appearance: "paintpalette"
            case .models: "cpu"
            case .quickAsk: "bolt"
            }
        }
    }

    var body: some View {
        GeometryReader { window in
            ZStack {
                // The window behind, dimmed; a click there closes the board.
                Rectangle()
                    .fill(.black.opacity(0.4))
                    .ignoresSafeArea()
                    .onTapGesture { close() }
                    .accessibilityHidden(true)
                board
                    // Largest 860 × 620; smaller windows get a 24-point margin all round.
                    .frame(width: min(860, window.size.width - Space.xxl * 2),
                           height: min(620, window.size.height - Space.xxl * 2))
            }
            .frame(width: window.size.width, height: window.size.height)
        }
        .onExitCommand { close() }
    }

    private var board: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: Space.xs) {
                Text("Settings")
                    .font(.system(.title2, design: .serif))
                    .padding(.horizontal, Space.sm)
                    .padding(.bottom, Space.md)
                ForEach(BoardSection.allCases) { item in
                    Button { section = item } label: {
                        Label(item.title, systemImage: item.symbol)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, Space.sm)
                            .frame(height: 28)
                            .background(section == item ? AnyShapeStyle(Palette.accent.opacity(0.16)) : AnyShapeStyle(.clear),
                                        in: RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(section == item ? .isSelected : [])
                }
                Spacer()
            }
            .padding(Space.lg)
            .frame(width: 200)
            .background(.background.secondary)

            Divider()

            VStack(spacing: 0) {
                HStack {
                    Text(section.title).font(.headline)
                    Spacer()
                    Button("Close", systemImage: "xmark") { close() }
                        .labelStyle(.iconOnly)
                        .buttonStyle(.borderless)
                        .keyboardShortcut(.cancelAction)
                        .help("Close Settings (⎋)")
                }
                .padding(.horizontal, Space.xl)
                .padding(.vertical, Space.md)
                Divider()
                Form {
                    switch section {
                    case .profile: ProfileSettings()
                    case .appearance: AppearanceSettings()
                    case .models: ModelsSettings()
                    case .quickAsk: QuickAskSettings()
                    }
                }
                .formStyle(.grouped)
            }
        }
        .background(.background)
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).strokeBorder(.separator))
        .shadow(color: .black.opacity(0.25), radius: 30, y: 12)
        .accessibilityAddTraits(.isModal)
        .onAppear {
            if let start = model.settingsBoardStart { section = start; model.settingsBoardStart = nil }
        }
    }

    private func close() {
        model.showingSettings = false
    }
}

/// Settings > Profile: who you are on this Mac, and the other profiles.
struct ProfileSettings: View {
    @State private var editing = false
    @State private var adding = false
    private var profiles = ProfileStore.shared

    var body: some View {
        Section {
            HStack(spacing: Space.lg) {
                ProfileBadge(profile: profiles.current, size: 56)
                VStack(alignment: .leading, spacing: Space.xs) {
                    Text(profiles.current.name).font(.title3.weight(.semibold))
                    Text(profiles.current.hasPassword ? "Protected with a password" : "No password")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Edit Profile…") { editing = true }
            }
            .padding(.vertical, Space.xs)
        } footer: {
            Text("Your conversations stay on this Mac, in this profile only. Models are shared by every profile.")
                .foregroundStyle(.secondary)
        }
        Section("Profiles on This Mac") {
            ForEach(profiles.list.profiles) { profile in
                HStack(spacing: Space.md) {
                    ProfileBadge(profile: profile, size: 24)
                    Text(profile.name)
                    Spacer()
                    if profile.id == profiles.current.id {
                        Text("Current").foregroundStyle(.secondary)
                    } else {
                        Button("Switch") { profiles.switchTo(profile.id) }
                    }
                }
            }
            Button("Add Profile…") { adding = true }
        }
        .sheet(isPresented: $editing) { EditProfileSheet() }
        .sheet(isPresented: $adding) { AddProfileSheet() }
    }
}
