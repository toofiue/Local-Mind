import AppKit
import LanternKit
import SwiftUI

/// The bottom of the sidebar: one row with who you are,
/// opening a menu with profiles, Models, Settings, and Lock. One target, nothing to mis-click.
struct SidebarFooter: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openSettings) private var openSettings
    @State private var addingProfile = false
    @State private var editingProfile = false
    @State private var hovering = false
    private var profiles = ProfileStore.shared

    var body: some View {
        Menu {
            Section(profiles.list.profiles.count > 1 ? "Switch Profile" : "Profile") {
                ForEach(profiles.list.profiles) { profile in
                    Button {
                        profiles.switchTo(profile.id)
                    } label: {
                        if profile.id == profiles.current.id {
                            Label(profile.name, systemImage: "checkmark")
                        } else {
                            Text(profile.name)
                        }
                    }
                }
                Button("Add Profile…") { addingProfile = true }
            }
            Divider()
            Button("Edit Profile…") { editingProfile = true }
            Button("Models") { model.showModels() }
                .keyboardShortcut("l", modifiers: [.command, .shift])
            Button("Settings…") { openSettings() }
                .keyboardShortcut(",")
            if profiles.current.hasPassword {
                Divider()
                Button("Lock") { model.isLocked = true }
            }
        } label: {
            HStack(spacing: Space.md) {
                ProfileBadge(profile: profiles.current, size: 32)
                VStack(alignment: .leading, spacing: 0) {
                    Text(profiles.current.name)
                        .font(.body.weight(.medium))
                        .lineLimit(1)
                    Text(profiles.current.hasPassword ? "Private profile" : "On this Mac")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: Space.sm)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, Space.sm)
            .padding(.vertical, Space.sm)
            .background(hovering ? AnyShapeStyle(.fill.tertiary) : AnyShapeStyle(.clear),
                        in: RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            .contentShape(Rectangle())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .onHover { hovering = $0 }
        .help("Profiles, Models, and Settings")
        .accessibilityLabel("Profile: \(profiles.current.name)")
        .padding(.horizontal, Space.sm)
        .padding(.vertical, Space.sm)
        .sheet(isPresented: $addingProfile) { AddProfileSheet() }
        .sheet(isPresented: $editingProfile) { EditProfileSheet() }
    }
}

/// A round badge with the profile's first letter, in the accent.
struct ProfileBadge: View {
    let profile: Profile
    var size: CGFloat = 24
    private var profiles = ProfileStore.shared

    init(profile: Profile, size: CGFloat = 24) {
        self.profile = profile
        self.size = size
    }

    var body: some View {
        Group {
            if let photo = profiles.photo(for: profile.id) {
                Image(nsImage: photo)
                    .resizable()
                    .scaledToFill()
            } else {
                Text(profile.initial)
                    .font(.system(size: size * 0.46, weight: .semibold)) // grid: ok scales with the badge
                    .foregroundStyle(Palette.onAccent)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Palette.accent)
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay(Circle().strokeBorder(.separator, lineWidth: 0.5)) // grid: ok hairline ring
        .accessibilityHidden(true)
    }
}

/// Shown instead of the window's content while a profile with a password is locked.
struct LockView: View {
    @Environment(AppModel.self) private var model
    @State private var password = ""
    @State private var wrong = false
    @State private var addingProfile = false
    @FocusState private var focused: Bool
    private var profiles = ProfileStore.shared

    var body: some View {
        VStack(spacing: Space.xl) {
            ProfileBadge(profile: profiles.current, size: 64)
            VStack(spacing: Space.xs) {
                Text(profiles.current.name)
                    .font(.system(.largeTitle, design: .serif))
                Text("Enter your password to see your conversations.")
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: Space.sm) {
                SecureField("Password", text: $password)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 240)
                    .focused($focused)
                    .onSubmit(unlock)
                Button("Unlock", action: unlock)
                    .keyboardShortcut(.defaultAction)
                    .disabled(password.isEmpty)
            }
            if wrong {
                Label("That password isn't right.", systemImage: "exclamationmark.circle")
                    .foregroundStyle(.secondary)
            }
            if profiles.list.profiles.count > 1 {
                Menu("Switch Profile") {
                    ForEach(profiles.list.profiles.filter { $0.id != profiles.current.id }) { profile in
                        Button(profile.name) { profiles.switchTo(profile.id) }
                    }
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }
        }
        .padding(Space.section)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { focused = true }
    }

    private func unlock() {
        if profiles.checkPassword(password, for: profiles.current.id) {
            password = ""
            wrong = false
            model.isLocked = false
        } else {
            wrong = true
            password = ""
        }
    }
}

/// Makes a new profile with its own conversations, then opens it.
struct AddProfileSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var password = ""
    @State private var confirm = ""
    @State private var problem: String?
    private var profiles = ProfileStore.shared

    var body: some View {
        Form {
            Section {
                TextField("Name", text: $name)
                SecureField("Password", text: $password, prompt: Text("Optional"))
                if !password.isEmpty {
                    SecureField("Confirm", text: $confirm)
                }
            } header: {
                Text("New Profile")
            } footer: {
                Text("A profile has its own conversations. Models are shared. With a password, others need it to open this profile.")
                    .foregroundStyle(.secondary)
            }
            if let problem {
                Label(problem, systemImage: "exclamationmark.circle").foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: Layout.renameSheet)
        .fitsContent()
        .noInitialFocus()
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("Add and Open", action: add).disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
    }

    private func add() {
        guard password == confirm || password.isEmpty else { problem = "The passwords don't match."; return }
        guard let profile = profiles.add(name: name, password: password) else { problem = "Choose a name no other profile uses."; return }
        dismiss()
        profiles.switchTo(profile.id)
    }
}

/// Changes the current profile's name or password, or removes the profile.
struct EditProfileSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var name = ProfileStore.shared.current.name
    @State private var current = ""
    @State private var newPassword = ""
    @State private var confirm = ""
    @State private var problem: String?
    @State private var confirmingRemoval = false
    private var profiles = ProfileStore.shared

    var body: some View {
        Form {
            Section("Profile") {
                LabeledContent("Photo") {
                    HStack(spacing: Space.md) {
                        ProfileBadge(profile: profiles.current, size: 40)
                        Button("Choose…", action: choosePhoto)
                        if profiles.photo(for: profiles.current.id) != nil {
                            Button("Remove") { profiles.removePhoto(for: profiles.current.id) }
                        }
                    }
                }
                TextField("Name", text: $name)
            }
            Section {
                if profiles.current.hasPassword {
                    SecureField("Current Password", text: $current)
                }
                SecureField(profiles.current.hasPassword ? "New Password" : "Password", text: $newPassword,
                            prompt: Text(profiles.current.hasPassword ? "Leave empty to remove it" : "Optional"))
                if !newPassword.isEmpty {
                    SecureField("Confirm", text: $confirm)
                }
            } header: {
                Text("Password")
            }
            if !profiles.current.isOriginal {
                Section {
                    Button("Remove This Profile…", role: .destructive) { confirmingRemoval = true }
                } footer: {
                    Text("Its conversations move to the Trash, so you can still put them back.")
                        .foregroundStyle(.secondary)
                }
            }
            if let problem {
                Label(problem, systemImage: "exclamationmark.circle").foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: Layout.renameSheet)
        .fitsContent()
        .noInitialFocus()
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) { Button("Save", action: save) }
        }
        .confirmationDialog("Remove “\(profiles.current.name)”?", isPresented: $confirmingRemoval) {
            Button("Remove Profile", role: .destructive) {
                let id = profiles.current.id
                dismiss()
                profiles.remove(id)
                ProfileStore.relaunch()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Its conversations move to the Trash.")
        }
    }

    private func choosePhoto() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.message = "Choose a photo for your profile"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        if !profiles.setPhoto(from: url, for: profiles.current.id) { problem = "That file isn't a picture Local Mind can read." }
    }

    private func save() {
        let id = profiles.current.id
        let changingPassword = !newPassword.isEmpty || (profiles.current.hasPassword && !current.isEmpty)
        if changingPassword {
            guard profiles.checkPassword(current, for: id) else { problem = "The current password isn't right."; return }
            guard newPassword == confirm || newPassword.isEmpty else { problem = "The new passwords don't match."; return }
        }
        guard profiles.rename(id, to: name) else { problem = "Choose a name no other profile uses."; return }
        if changingPassword { profiles.setPassword(newPassword, for: id) }
        dismiss()
    }
}
