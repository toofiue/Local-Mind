import AppKit
import SwiftUI

/// The message field. A real text view, so fast typing, paste, undo, and input
/// methods all behave. Return submits and Shift-Return adds a line.
struct ComposerField: NSViewRepresentable {
    @Binding var text: String
    @Binding var height: CGFloat
    let isEnabled: Bool
    let focusRequest: Int
    let maxLines: Int
    let onSubmit: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        guard let textView = scrollView.documentView as? NSTextView else { return scrollView }
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
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        context.coordinator.parent = self
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
