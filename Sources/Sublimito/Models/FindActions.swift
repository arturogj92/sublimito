import AppKit

/// Acciones de búsqueda del menú. En el editor Monaco usan su find widget
/// (con regex, case y whole word). En el visor de ficheros grandes, el find bar nativo.
enum FindActions {
    @MainActor
    static func send(_ command: MonacoController.FindCommand) {
        guard let buffer = AppState.shared.activeBuffer else { return }
        if buffer.isLargeFile {
            // El visor usa NSTextView con find bar nativo
            if let textView = nativeTextView(in: NSApp.keyWindow?.contentView) {
                NSApp.keyWindow?.makeFirstResponder(textView)
                let item = NSMenuItem()
                item.tag = NSTextFinder.Action.showFindInterface.rawValue
                textView.performTextFinderAction(item)
            }
            return
        }
        MonacoController.shared.runFind(command)
    }

    @MainActor
    private static func nativeTextView(in view: NSView?) -> NSTextView? {
        guard let view else { return nil }
        if let tv = view as? NSTextView, tv.usesFindBar { return tv }
        for sub in view.subviews {
            if let found = nativeTextView(in: sub) { return found }
        }
        return nil
    }
}
