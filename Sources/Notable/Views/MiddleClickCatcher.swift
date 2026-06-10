import SwiftUI
import AppKit

/// Captura SOLO los clics del botón central del ratón y deja pasar el resto
/// de eventos a las vistas de debajo. Se usa para cerrar pestañas con la rueda.
struct MiddleClickCatcher: NSViewRepresentable {
    let action: () -> Void

    func makeNSView(context: Context) -> CatcherView {
        let view = CatcherView()
        view.action = action
        return view
    }

    func updateNSView(_ view: CatcherView, context: Context) {
        view.action = action
    }

    final class CatcherView: NSView {
        var action: (() -> Void)?

        override func hitTest(_ point: NSPoint) -> NSView? {
            if let event = NSApp.currentEvent,
               event.type == .otherMouseDown || event.type == .otherMouseUp || event.type == .otherMouseDragged {
                return super.hitTest(point)
            }
            return nil
        }

        override func otherMouseUp(with event: NSEvent) {
            if event.buttonNumber == 2 {
                action?()
            } else {
                super.otherMouseUp(with: event)
            }
        }
    }
}
