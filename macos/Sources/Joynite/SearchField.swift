import AppKit
import SwiftUI

@MainActor final class SearchFieldHandle: ObservableObject {
    weak var field: NSTextField?
    func focus() { if let field { field.isEditable = true; field.isSelectable = true; field.window?.makeFirstResponder(field) } }
    func blur() { field?.window?.makeFirstResponder(nil) }
}
struct PersistentSearchField: NSViewRepresentable {
    @Binding var text: String
    let expanded: Bool
    let handle: SearchFieldHandle
    let onFocus: () -> Void
    let onSubmit: () -> Void
    let onCancel: () -> Void
    let onNavigate: (Int) -> Void
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField()
        field.isEditable = false; field.isSelectable = false
        field.placeholderString = "Find a game"; field.isBordered = false; field.drawsBackground = false
        field.textColor = .white; field.focusRingType = .none; field.usesSingleLineMode = true
        field.setAccessibilityLabel("Find a game")
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        field.setContentHuggingPriority(.defaultLow, for: .horizontal)
        field.delegate = context.coordinator; handle.field = field
        return field
    }
    func updateNSView(_ field: NSTextField, context: Context) {
        context.coordinator.parent = self
        field.isEditable = expanded; field.isSelectable = expanded
        if field.stringValue != text { field.stringValue = text }
        field.font = .systemFont(ofSize: expanded ? 27 : 13, weight: .medium)
    }
    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: PersistentSearchField
        init(_ parent: PersistentSearchField) { self.parent = parent }
        func controlTextDidBeginEditing(_ notification: Notification) { parent.onFocus() }
        func controlTextDidChange(_ notification: Notification) { if let field = notification.object as? NSTextField { parent.text = field.stringValue } }
        func control(_ control: NSControl, textView: NSTextView, doCommandBy command: Selector) -> Bool {
            switch command {
            case #selector(NSResponder.insertNewline(_:)): parent.onSubmit(); return true
            case #selector(NSResponder.cancelOperation(_:)): parent.onCancel(); return true
            case #selector(NSResponder.moveDown(_:)): parent.onNavigate(1); return true
            case #selector(NSResponder.moveUp(_:)): parent.onNavigate(-1); return true
            default: return false
            }
        }
    }
}
