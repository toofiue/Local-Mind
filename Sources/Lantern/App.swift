import AppKit
import SwiftData
import SwiftUI

// Lantern
//   Lantern                      the app
//   APP_STORE=<file> Lantern     use another database (tests, experiments)
//   APP_OLLAMA_URL=<url>         with APP_STORE, talk to another address instead of local Ollama
//   APP_SNAPSHOT=<dir> Lantern   save a PNG of every page and Settings tab in light and dark mode, then quit
//   APP_SEED=1 Lantern           fill an empty /tmp store with sample conversations (tools/snap.sh)
//   Lantern --selftest           run the self-test on a /tmp store and quit with 0 or 1 (tools/selftest.sh)
//   APP_SELFTEST_LIVE=<model>    also run one real reply through local Ollama in the self-test
//   APP_ACCENT=<id> Lantern      run with another accent from Theme.all (UI/Theme.swift)
//   APP_GRID=1 Lantern           draw the 8 pt grid and the layout probes over the window

@main
struct LanternApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var model = AppModel(container: Store.makeContainer())
    @ObservedObject private var menu = MenuState.shared

    var body: some Scene {
        Window("Lantern", id: "main") {
            ContentView()
                .environment(model)
                .themed()
                .overlay { if GridOverlay.enabled { GridOverlay() } }
                .frame(minWidth: 760, minHeight: 480)
        }
        .modelContainer(model.container)
        .defaultSize(width: 1100, height: 720)
        .windowToolbarStyle(.unified)
        .commands {
            SidebarCommands()
            ToolbarCommands()
            CommandGroup(replacing: .newItem) {
                Button("New Conversation") { model.newConversation() }
                    .keyboardShortcut("n")
            }
            CommandMenu("Conversation") {
                Button("Choose Model…") { model.showingModelPicker.toggle() }
                    .keyboardShortcut("m", modifiers: [.command, .shift])
                    .disabled(menu.isWriting)
                Divider()
                Button("Stop") { model.stop() }
                    .keyboardShortcut(".")
                    .disabled(!menu.isWriting)
                Button("Retry") { model.retry() }
                    .keyboardShortcut("r")
                    .disabled(menu.isWriting || !menu.hasReply)
                Button("Copy Reply") { model.copyLatestReply() }
                    .keyboardShortcut("c", modifiers: [.command, .shift])
                    .disabled(!menu.hasReply)
                Divider()
                Button("Rename") { model.startRenaming() }
                    .keyboardShortcut("r", modifiers: [.command, .shift])
                    .disabled(!menu.hasSelection)
                Button(menu.isPinned ? "Unpin" : "Pin") { model.togglePin() }
                    .keyboardShortcut("p", modifiers: [.command, .shift])
                    .disabled(!menu.hasSelection)
                Divider()
                // No shortcut here: the Delete key must keep working in text fields.
                // The sidebar handles it with onDeleteCommand.
                Button("Delete") { model.requestDelete() }
                    .disabled(!menu.canDelete)
            }
        }

        Settings {
            SettingsView()
                .environment(model)
                .themed()
        }
        .windowResizability(.contentSize)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Started from a terminal, the process is not a foreground app yet.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    /// The self-test's result becomes the exit code, after a normal quit.
    func applicationWillTerminate(_ notification: Notification) {
        if SelfTest.requested { exit(SelfTest.exitCode) }
    }
}

/// Where the data lives: ~/Library/Application Support/Lantern/Lantern.store
enum Store {
    /// True when APP_STORE points somewhere else (tests, snapshots, seed data).
    static var isOverridden: Bool {
        !(ProcessInfo.processInfo.environment["APP_STORE"] ?? "").isEmpty
    }

    static var url: URL {
        if let path = ProcessInfo.processInfo.environment["APP_STORE"], !path.isEmpty {
            return URL(fileURLWithPath: path)
        }
        let dir = URL.applicationSupportDirectory.appending(path: "Lantern", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appending(path: "Lantern.store")
    }

    static func makeContainer() -> ModelContainer {
        do {
            return try ModelContainer(for: Conversation.self, Message.self, configurations: ModelConfiguration(url: url))
        } catch {
            fatalError("Could not open the database at \(url.path): \(error)")
        }
    }
}
