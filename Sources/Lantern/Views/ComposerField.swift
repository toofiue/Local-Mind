import AppKit
import SwiftUI

/// Sends pasted files and images to the conversation instead of inserting
/// them as text. Drops are left for the conversation page to handle.
private final class ComposerTextView: NSTextView {
    var onPasteFiles: (([URL]) -> Void)?
    var onPasteImage: ((Data) -> Void)?

    override var acceptableDragTypes: [NSPasteboard.PasteboardType] { [] }
    override func updateDragTypeRegistration() { unregisterDraggedTypes() }

    override func paste(_ sender: Any?) {
        let board = NSPasteboard.general
        let files = board.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
        if !files.isEmpty {
            onPasteFiles?(files)
        } else if board.string(forType: .string) == nil, let image = board.data(forType: .png) ?? board.data(forType: .tiff) {
            onPasteImage?(image)
        } else {
            super.paste(sender)
        }
    }
}

/// The message field. A real text view, so fast typing, paste, undo, and input
/// methods all behave. Return submits and Shift-Return adds a line.
struct ComposerField: NSViewRepresentable {
    @Binding var text: String
    @Binding var height: CGFloat
    let isEnabled: Bool
    let focusRequest: Int
    let maxLines: Int
    let onSubmit: () -> Void
    var onPasteFiles: ([URL]) -> Void = { _ in }
    var onPasteImage: (Data) -> Void = { _ in }
    var onEscape: (() -> Void)?

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let textView = ComposerTextView()
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = .width
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: .greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = true
        textView.delegate = context.coordinator
        textView.font = .preferredFont(forTextStyle: .body)
        textView.textColor = .labelColor
        textView.drawsBackground = false
        textView.isRichText = false
        textView.allowsUndo = true
        textView.textContainerInset = .zero
        textView.textContainer?.lineFragmentPadding = 0
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.setAccessibilityLabel("Message")
        textView.unregisterDraggedTypes()

        let scrollView = NSScrollView()
        scrollView.documentView = textView
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? ComposerTextView else { return }
        context.coordinator.parent = self
        textView.onPasteFiles = onPasteFiles
        textView.onPasteImage = onPasteImage
        if textView.string != text {
            textView.string = text
            // After this update, once layout has caught up with the new text.
            DispatchQueue.main.async { context.coordinator.updateHeight(of: textView) }
        }
        textView.isEditable = isEnabled
        if context.coordinator.handledFocusRequest != focusRequest {
            context.coordinator.handledFocusRequest = focusRequest
            DispatchQueue.main.async {
                // Arrow keys in the sidebar must keep moving through the list.
                if NSApp.currentEvent?.type != .keyDown { textView.window?.makeFirstResponder(textView) }
            }
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: ComposerField
        var handledFocusRequest = -1

        init(_ parent: ComposerField) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            parent.text = textView.string
            updateHeight(of: textView)
        }

        func textView(_ textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            if selector == #selector(NSResponder.cancelOperation(_:)) || selector == #selector(NSResponder.complete(_:)), let onEscape = parent.onEscape {
                onEscape()
                return true
            }
            guard selector == #selector(NSResponder.insertNewline(_:)) else { return false }
            if NSApp.currentEvent?.modifierFlags.contains(.shift) == true {
                textView.insertNewlineIgnoringFieldEditor(nil)
            } else {
                parent.onSubmit()
            }
            return true
        }

        func updateHeight(of textView: NSTextView) {
            guard let layout = textView.layoutManager, let container = textView.textContainer,
                  let font = textView.font else { return }
            layout.ensureLayout(for: container)
            let line = layout.defaultLineHeight(for: font)
            let used = textView.string.isEmpty ? line : layout.usedRect(for: container).height
            let height = min(max(used, line), line * CGFloat(parent.maxLines)).rounded(.up)
            if abs(height - parent.height) >= 1 { parent.height = height }
        }
    }
}
