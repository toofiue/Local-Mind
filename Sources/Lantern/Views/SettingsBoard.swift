import SwiftUI

/// Settings inside the main window: a board in the middle over a dimmed window.
/// A title bar across the top with a close button; on the left a search field and the sections
/// in groups; on the right the chosen section as rows. It has a largest size and shrinks with a
/// small window, keeping a margin all round. Escape, the close button, or a click outside closes it.
struct SettingsBoard: View {
    @Environment(AppModel.self) private var model
    @State private var search = ""

    enum BoardSection: String, CaseIterable, Identifiable {
        case profile, models, appearance, general
        var id: String { rawValue }
        var title: String {
            switch self {
            case .profile: "Profile"
            case .models: "Models"
            case .appearance: "Appearance"
            case .general: "General"
            }
        }
        var symbol: String {
            switch self {
            case .profile: "person"
            case .models: "cpu"
            case .appearance: "paintpalette"
            case .general: "gearshape"
            }
        }
        /// Words that find this section in Search.
        var keywords: [String] {
            switch self {
            case .profile: ["name", "photo", "password", "lock", "account", "switch"]
            case .appearance: ["dark", "light", "theme", "color", "accent", "sidebar", "frost", "transparency"]
            case .models: ["default", "loaded", "memory", "test", "benchmark", "best", "rename", "unload"]
            case .general: ["shortcut", "hotkey", "keyboard", "quick ask", "menu bar"]
            }
        }
        /// The sidebar's groups, split by lines.
        static let groups: [[BoardSection]] = [[.profile], [.models], [.appearance, .general]]
    }

    private func matches(_ item: BoardSection) -> Bool {
        let query = search.trimmingCharacters(in: .whitespaces).lowercased()
        guard !query.isEmpty else { return true }
        return item.title.lowercased().contains(query) || item.keywords.contains { $0.contains(query) }
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
                    // Largest 900 × 640; smaller windows get a 24-point margin all round.
                    .frame(width: min(900, window.size.width - Space.xxl * 2),
                           height: min(640, window.size.height - Space.xxl * 2))
            }
            .frame(width: window.size.width, height: window.size.height)
        }
        .onExitCommand { close() }
    }

    private var board: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Settings")
                    .font(.title3)
                Spacer()
                Button("Close", systemImage: "xmark") { close() }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
                    .keyboardShortcut(.cancelAction)
                    .help("Close Settings (⎋)")
            }
            .padding(.horizontal, Space.xl)
            .frame(height: 52)
            Divider()
            HStack(spacing: 0) {
                sidebar
                Divider()
                page
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    // One rule for every section: the accent for selection controls (pickers, switches,
                    // the chosen segment), neutral gray for plain buttons.
                    .buttonStyle(SettingsButtonStyle())
            }
        }
        .background(.background)
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).strokeBorder(.separator))
        .shadow(color: .black.opacity(0.3), radius: 30, y: 12)
        .accessibilityAddTraits(.isModal)
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            HStack(spacing: Space.sm) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                TextField("Search", text: $search, prompt: Text("Search"))
                    .textFieldStyle(.plain)
                    .onSubmit { if let first = BoardSection.allCases.first(where: matches) { model.settingsSection = first } }
            }
            .padding(.horizontal, Space.md)
            .frame(height: 32)
            .background(.fill.tertiary, in: RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            .padding(.bottom, Space.md)
            let groups = BoardSection.groups.map { $0.filter(matches) }.filter { !$0.isEmpty }
            ForEach(Array(groups.enumerated()), id: \.offset) { index, group in
                if index > 0 {
                    Divider().padding(.horizontal, Space.sm).padding(.vertical, Space.sm)
                }
                ForEach(group) { item in
                    Button { model.settingsSection = item } label: {
                        Label(item.title, systemImage: item.symbol)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, Space.md)
                            .frame(height: 32)
                            .background(model.settingsSection == item ? AnyShapeStyle(.fill.secondary) : AnyShapeStyle(.clear),
                                        in: RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(model.settingsSection == item ? .isSelected : [])
                }
            }
            if groups.isEmpty {
                Text("No settings match “\(search)”.")
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, Space.sm)
            }
            Spacer()
        }
        .padding(Space.lg)
        .frame(width: 220)
    }

    @ViewBuilder private var page: some View {
        switch model.settingsSection {
        case .profile: ProfileSettings()
        case .models: ModelsSettings()
        case .appearance: AppearanceSettings()
        case .general: GeneralSettings()
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
        SettingsPageLayout(title: "Profile") {
            HStack(spacing: Space.lg) {
                ProfileBadge(profile: profiles.current, size: 56)
                VStack(alignment: .leading, spacing: Space.xs) {
                    Text(profiles.current.name).font(.title3)
                    Text(profiles.current.hasPassword ? "Protected with a password" : "No password")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Edit Profile…") { editing = true }
            }
            .padding(.vertical, Space.lg)
            Divider()
            SettingRow(title: "Your conversations",
                       description: "They stay on this Mac, in this profile only. Models are shared by every profile.") {
                EmptyView()
            }
            Text("Profiles on This Mac")
                .font(.title3)
                .padding(.top, Space.xl)
                .padding(.bottom, Space.sm)
            ForEach(profiles.list.profiles) { profile in
                VStack(spacing: 0) {
                    HStack(spacing: Space.md) {
                        ProfileBadge(profile: profile, size: 28)
                        Text(profile.name)
                        Spacer()
                        if profile.id == profiles.current.id {
                            Text("Current").foregroundStyle(.secondary)
                        } else {
                            Button("Switch") { profiles.switchTo(profile.id) }
                        }
                    }
                    .padding(.vertical, Space.md)
                    Divider()
                }
            }
            Button("Add Profile…") { adding = true }
                .padding(.top, Space.md)
        }
        .sheet(isPresented: $editing) { EditProfileSheet() }
        .sheet(isPresented: $adding) { AddProfileSheet() }
    }
}
