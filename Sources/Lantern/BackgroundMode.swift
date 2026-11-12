import AppKit
import ServiceManagement

/// Local Mind keeps running after its window closes, like a menu bar app: it leaves the Dock,
/// and Quick Ask and the menu bar aperture keep working. Opening the window brings the Dock icon back.
enum AppPresence {
    /// True for the main window, not Quick Ask, menus, or sheets.
    static func isMainWindow(_ window: NSWindow) -> Bool {
        !(window is NSPanel) && window.canBecomeMain && window.styleMask.contains(.titled) && window.sheetParent == nil
    }

    static var hasOpenMainWindow: Bool {
        NSApp.windows.contains { isMainWindow($0) && $0.isVisible }
    }

    /// Back in the Dock and the app switcher, for as long as a window is open.
    static func showInDock() {
        if NSApp.activationPolicy() != .regular { NSApp.setActivationPolicy(.regular) }
    }

    /// Runs on quietly in the menu bar once no window is left.
    static func leaveDockIfNoWindows() {
        guard !SelfTest.requested, !Snapshot.requested, !hasOpenMainWindow else { return }
        NSApp.setActivationPolicy(.accessory)
    }

    /// True when macOS started the app as a login item, so it should start in the background.
    static var launchedAtLogin: Bool {
        guard let event = NSAppleEventManager.shared().currentAppleEvent else { return false }
        return event.eventID == kAEOpenApplication
            && event.paramDescriptor(forKeyword: keyAEPropData)?.enumCodeValue == keyAELaunchedAsLogInItem
    }
}

/// Opening Local Mind when you log in, so the Quick Ask shortcut always works.
enum LoginItem {
    static var isEnabled: Bool { SMAppService.mainApp.status == .enabled }

    /// Returns a short reason when macOS refuses.
    @discardableResult
    static func set(_ enabled: Bool) -> String? {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            return nil
        } catch {
            return enabled ? "macOS didn't allow it. Check System Settings > General > Login Items." : nil
        }
    }
}
