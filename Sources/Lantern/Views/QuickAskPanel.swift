import AppKit
import Observation
import SwiftUI

/// What Quick Ask is showing.
@Observable
final class QuickAskState {
    var draft = ""
    var fieldHeight: CGFloat = Space.lg
    var focusRequest = 0
    /// The conversation this Quick Ask has started, once you've sent something.
    var conversation: Conversation?
    /// The model picked for this Quick Ask, before anything has been sent.
    var modelName: String?
    /// Why the last message couldn't be sent.
    var notice: String?
}

private final class QuickPanel: NSPanel {
    var onDismiss: () -> Void = {}

    init() {
        super.init(contentRect: NSRect(x: 0, y: 0, width: Layout.quickPanel, height: Layout.quickPanelStart),
                   styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
                   backing: .buffered, defer: false)
        isFloatingPanel = true
        level = .floating
        hidesOnDeactivate = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isMovableByWindowBackground = true
    }

    override var canBecomeKey: Bool { true }

    // Clicking another app leaves Quick Ask open, with what you typed. Escape or the shortcut closes it.

    override func cancelOperation(_ sender: Any?) {
        onDismiss()
    }
}

/// Owns the floating panel: showing, hiding, placing, and sizing it.
final class QuickAskController {
    static let shared = QuickAskController()

    private var panel: QuickPanel?
    private var model: AppModel?

    var isVisible: Bool { panel?.isVisible ?? false }
    var window: NSWindow? { panel }

    func configure(model: AppModel) {
        guard panel == nil else { return }
        self.model = model
        let panel = QuickPanel()
        panel.onDismiss = { [weak self] in self?.hide() }
        let host = NSHostingView(rootView: QuickAskView()
            .environment(model)
            .modelContainer(model.container)
            .themed())
        host.sizingOptions = []
        panel.contentView = host
        self.panel = panel
        // Drag it anywhere by its background; it opens there next time.
        NotificationCenter.default.addObserver(forName: NSWindow.didMoveNotification, object: panel, queue: .main) { note in
            guard let moved = note.object as? NSWindow else { return }
            MainActor.assumeIsolated {
                // Test runs move it too; that's not where you put it.
                guard !SelfTest.requested, !Snapshot.requested else { return }
                UserDefaults.standard.set([moved.frame.minX, moved.frame.maxY], forKey: Self.positionKey)
            }
        }
    }

    private static let positionKey = "quickAsk.topLeft"

    func toggle() {
        if isVisible { hide() } else { show() }
    }

    func show() {
        guard let panel, let model else { return }
        // A locked profile's conversations stay hidden: open the window to unlock instead.
        if model.isLocked {
            model.showMainWindow()
            return
        }
        // Fresh each time, unless a reply is still being written here.
        let quick = model.quickAsk
        if let conversation = quick.conversation, !model.replies.isWriting(in: conversation) { quick.conversation = nil }
        if quick.conversation == nil { quick.modelName = nil }
        quick.notice = nil
        panel.setFrame(startingFrame(height: panel.frame.height), display: true)
        panel.orderFrontRegardless()
        panel.makeKey()
        model.quickAsk.focusRequest += 1
    }

    func hide() {
        panel?.orderOut(nil)
    }

    /// Grows and shrinks downward, so the field stays put, unless that would run off the screen.
    func resize(height: CGFloat) {
        guard let panel, abs(panel.frame.height - height) >= 1 else { return }
        var frame = panel.frame
        frame.origin.y += frame.height - height
        frame.size.height = height
        panel.setFrame(Self.onScreen(frame), display: true)
    }

    private var dragStart: (mouse: NSPoint, origin: NSPoint)?

    /// Follows the pointer, clamped to the visible screen it's on, so no part goes off screen.
    func drag() {
        guard let panel else { return }
        let mouse = NSEvent.mouseLocation
        if dragStart == nil { dragStart = (mouse, panel.frame.origin) }
        guard let start = dragStart else { return }
        var frame = panel.frame
        frame.origin = NSPoint(x: start.origin.x + mouse.x - start.mouse.x, y: start.origin.y + mouse.y - start.mouse.y)
        panel.setFrameOrigin(Self.onScreen(frame, near: mouse).origin)
    }

    func endDrag() {
        dragStart = nil
    }

    /// Moves a frame just enough to sit inside the visible area (inside the menu bar and the Dock)
    /// of the screen under `point`, or the screen the frame is mostly on.
    static func onScreen(_ frame: NSRect, near point: NSPoint? = nil) -> NSRect {
        let screen = point.flatMap { p in NSScreen.screens.first { NSMouseInRect(p, $0.frame, false) } }
            ?? NSScreen.screens.max { $0.frame.intersection(frame).area < $1.frame.intersection(frame).area }
            ?? NSScreen.main
        guard let visible = screen?.visibleFrame else { return frame }
        var result = frame
        result.origin.x = min(max(frame.minX, visible.minX), visible.maxX - frame.width)
        result.origin.y = min(max(frame.minY, visible.minY), visible.maxY - frame.height)
        return result
    }

    /// Where you last left it, if that spot is still on a screen; otherwise centered near the top
    /// of the screen under the pointer.
    private func startingFrame(height: CGFloat) -> NSRect {
        if let saved = UserDefaults.standard.array(forKey: Self.positionKey) as? [CGFloat], saved.count == 2 {
            let frame = NSRect(x: saved[0], y: saved[1] - height, width: Layout.quickPanel, height: height)
            if NSScreen.screens.contains(where: { $0.visibleFrame.intersects(frame) }) { return Self.onScreen(frame) }
        }
        let pointer = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(pointer, $0.frame, false) } ?? NSScreen.main
        let visible = screen?.visibleFrame ?? .zero
        let top = visible.maxY - visible.height / 4
        return NSRect(x: visible.midX - Layout.quickPanel / 2, y: top - height, width: Layout.quickPanel, height: height)
    }
}

struct QuickAskView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var quick = model.quickAsk
        VStack(spacing: 0) {
            HStack(spacing: Space.md) {
                ComposerField(text: $quick.draft, height: $quick.fieldHeight,
                              isEnabled: model.connection == .connected,
                              focusRequest: quick.focusRequest, maxLines: 6, onSubmit: { model.quickSend() },
                              onEscape: { QuickAskController.shared.hide() })
                    .frame(height: quick.fieldHeight)
                    .overlay(alignment: .topLeading) {
                        if quick.draft.isEmpty {
                            Text("Ask anything")
                                .foregroundStyle(.secondary)
                                .allowsHitTesting(false)
                        }
                    }
                QuickModelMenu()
                if let conversation = quick.conversation, model.replies.isWriting(in: conversation) {
                    Button("Stop", systemImage: "stop.fill") { model.stop() }
                        .labelStyle(.iconOnly)
                        .buttonStyle(.borderedProminent)
                        .buttonBorderShape(.circle)
                        .help("End this reply and keep its text so far")
                }
            }
            .padding(Space.lg)

            if let warning = model.memoryWarning, warning.surface == .quickAsk {
                MemoryWarningView(warning: warning) { model.quickSend(skipMemoryCheck: true) }
                    .padding([.horizontal, .bottom], Space.lg)
            }

            if let notice = quick.notice {
                Label(notice, systemImage: "exclamationmark.triangle")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding([.horizontal, .bottom], Space.lg)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if let conversation = quick.conversation {
                Divider()
                QuickAskConversation(conversation: conversation)
                Divider()
                HStack {
                    Spacer()
                    Button("Open in Window") { model.openQuickAskInWindow() }
                        .keyboardShortcut(.return, modifiers: .command)
                        .help("Continue this conversation in the main window (⌘↩)")
                }
                .padding(.horizontal, Space.lg)
                .padding(.vertical, Space.sm)
            }
        }
        .frame(width: Layout.quickPanel)
        // Drag any empty spot, like the edge around the message box, to move Quick Ask.
        // It stays fully on screen, and opens there next time.
        .background {
            Color.clear
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 2)
                    .onChanged { _ in QuickAskController.shared.drag() }
                    .onEnded { _ in QuickAskController.shared.endDrag() })
        }
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: Radius.lg))
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
            QuickAskController.shared.resize(height: height)
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }
}

/// The messages under the field. Grows with the reply, then scrolls.
private struct QuickAskConversation: View {
    let conversation: Conversation
    @State private var contentHeight: CGFloat = 0

    var body: some View {
        let messages = conversation.ordered
        let latestReplyID = messages.last { $0.role == .assistant }?.uid
        ScrollView {
            VStack(spacing: Space.lg) {
                ForEach(messages) { message in
                    MessageRow(message: message, isLatestReply: message.uid == latestReplyID)
                }
            }
            .padding(Space.lg)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { contentHeight = $0 }
        }
        .defaultScrollAnchor(.bottom)
        .frame(height: min(contentHeight, Layout.quickReply))
    }
}

/// A menu rather than a popover, so the panel keeps keyboard focus and stays open.
private struct QuickModelMenu: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Menu {
            ForEach(model.models) { item in
                Toggle(isOn: Binding(get: { model.quickModelName == item.name },
                                     set: { _ in model.chooseQuickModel(item.name) })) {
                    Text(model.displayName(item.name))
                    if model.modelNicknames[item.name] != nil { Text(item.name) }
                }
            }
        } label: {
            Text(model.quickModelName.map(model.displayName) ?? "No Models")
                .font(.caption)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .disabled(model.isWriting || model.models.isEmpty)
        .help("Choose which model answers here")
    }
}

private extension NSRect {
    var area: CGFloat { isNull ? 0 : width * height }
}
