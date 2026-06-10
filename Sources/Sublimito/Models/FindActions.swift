import AppKit

/// Lanza acciones del buscador nativo (find bar) sobre el editor de la ventana.
/// SwiftUI no añade los items de menú de Buscar, así que los ponemos a mano
/// y los enchufamos aquí a NSTextView.performTextFinderAction.
enum FindActions {
    @MainActor
    static func send(_ action: NSTextFinder.Action) {
        guard let window = NSApp.keyWindow else { return }
        let textView = (window.firstResponder as? NSTextView).flatMap { $0.usesFindBar ? $0 : nil }
            ?? editorTextView(in: window.contentView)
        guard let textView else { return }
        if window.firstResponder !== textView {
            window.makeFirstResponder(textView)
        }
        let item = NSMenuItem()
        item.tag = action.rawValue
        textView.performTextFinderAction(item)
    }

    @MainActor
    private static func editorTextView(in view: NSView?) -> NSTextView? {
        guard let view else { return nil }
        if let tv = view as? NSTextView, tv.usesFindBar { return tv }
        for sub in view.subviews {
            if let found = editorTextView(in: sub) { return found }
        }
        return nil
    }
}
