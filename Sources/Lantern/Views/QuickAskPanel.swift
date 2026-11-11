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
        level = .statusBar
        hidesOnDeactivate = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isMovableByWindowBackground = true
    }

    override var canBecomeKey: Bool { true }

    override func resignKey() {
        super.resignKey()
        onDismiss()
    }

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
    }

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

    /// Grows and shrinks downward, so the field stays put.
    func resize(height: CGFloat) {
        guard let panel, abs(panel.frame.height - height) >= 1 else { return }
        var frame = panel.frame
        frame.origin.y += frame.height - height
        frame.size.height = height
        panel.setFrame(frame, display: true)
    }

    /// Centered, in the top third of the screen under the pointer.
    private func startingFrame(height: CGFloat) -> NSRect {
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
