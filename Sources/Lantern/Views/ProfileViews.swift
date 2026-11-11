import LanternKit
import SwiftUI

/// The bottom of the sidebar: who you are (with switching and locking), Models, and Settings.
struct SidebarFooter: View {
    @Environment(AppModel.self) private var model
    @State private var addingProfile = false
    @State private var editingProfile = false
    private var profiles = ProfileStore.shared

    var body: some View {
        HStack(spacing: Space.xs) {
            Menu {
                Section("Profiles") {
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
                }
                Divider()
                Button("Add Profile…") { addingProfile = true }
                Button("Edit Profile…") { editingProfile = true }
                if profiles.current.hasPassword {
                    Divider()
                    Button("Lock") { model.isLocked = true }
                }
            } label: {
                HStack(spacing: Space.sm) {
                    ProfileBadge(profile: profiles.current, size: 24)
                    Text(profiles.current.name)
                        .lineLimit(1)
                }
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .fixedSize(horizontal: false, vertical: true)
            .help("Switch profiles, add one, or lock")
            .accessibilityLabel("Profile: \(profiles.current.name)")

            Spacer(minLength: Space.sm)

            Button { model.showModels() } label: {
                Image(systemName: "cpu")
            }
            .buttonStyle(.borderless)
            .foregroundStyle(model.showingModels ? Palette.accentText : .secondary)
            .help("Models (⇧⌘L)")
            .accessibilityLabel("Models")

            SettingsLink {
                Image(systemName: "gearshape")
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
            .help("Settings (⌘,)")
            .accessibilityLabel("Settings")
        }
        .font(.callout)
        .padding(.horizontal, Space.lg)
        .padding(.vertical, Space.md)
        .sheet(isPresented: $addingProfile) { AddProfileSheet() }
        .sheet(isPresented: $editingProfile) { EditProfileSheet() }
    }
}

/// A round badge with the profile's first letter, in the accent.
struct ProfileBadge: View {
    let profile: Profile
    var size: CGFloat = 24

    var body: some View {
        Text(profile.initial)
            .font(.system(size: size * 0.48, weight: .semibold)) // grid: ok scales with the badge
            .foregroundStyle(Palette.onAccent)
            .frame(width: size, height: size)
            .background(Palette.accent, in: Circle())
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
