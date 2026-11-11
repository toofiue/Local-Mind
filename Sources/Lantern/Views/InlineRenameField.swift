import AppKit
import SwiftUI

/// Renames in place, like Finder, but without the white box: the text sits right on the row.
/// Return or clicking away saves, Escape cancels, and the whole name starts selected.
/// SwiftUI's TextField can't do this, because macOS draws a white box behind any field being edited.
struct InlineRenameField: NSViewRepresentable {
    let title: String
    let onCommit: (String) -> Void
    let onCancel: () -> Void

    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField(string: title)
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = .preferredFont(forTextStyle: .body)
        field.lineBreakMode = .byTruncatingTail
        field.cell?.isScrollable = true
        field.delegate = context.coordinator
        field.setAccessibilityLabel("Conversation name")
        // A double-click's first click has just opened the chat, so take focus once that settles.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            guard let window = field.window, window.makeFirstResponder(field) else { return }
            if let editor = field.currentEditor() as? NSTextView {
                editor.drawsBackground = false
                editor.selectedTextAttributes = [.backgroundColor: NSColor(Palette.accent).withAlphaComponent(0.35)]
                editor.selectAll(nil)
            }
        }
        return field
    }

    func updateNSView(_ field: NSTextField, context: Context) {
        context.coordinator.parent = self
    }

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: InlineRenameField
        private var finished = false

        init(parent: InlineRenameField) { self.parent = parent }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            if selector == #selector(NSResponder.cancelOperation(_:)) {
                finished = true
                parent.onCancel()
                return true
            }
            return false
        }

        /// Return and clicking away both end editing here, and both save.
        func controlTextDidEndEditing(_ notification: Notification) {
            guard !finished, let field = notification.object as? NSTextField else { return }
            finished = true
            parent.onCommit(field.stringValue)
        }
    }
}
