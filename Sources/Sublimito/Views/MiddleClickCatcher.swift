import SwiftUI
import AppKit

/// Detecta clics del botón central del ratón sobre la zona de la vista usando un
/// monitor local de eventos. No participa en el hit-testing, así que nunca
/// interfiere con los clics y gestos normales (List de macOS incluido).
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
        private var monitor: Any?

        override func hitTest(_ point: NSPoint) -> NSView? {
            nil // transparente a todos los clics normales
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if window == nil {
                removeMonitor()
            } else if monitor == nil {
                monitor = NSEvent.addLocalMonitorForEvents(matching: [.otherMouseUp]) { [weak self] event in
                    guard let self,
                          event.buttonNumber == 2,
                          let window = self.window,
                          event.window === window,
                          !self.isHiddenOrHasHiddenAncestor else { return event }
                    let point = self.convert(event.locationInWindow, from: nil)
                    guard self.bounds.contains(point) else { return event }
                    self.action?()
                    return nil
                }
            }
        }

        private func removeMonitor() {
            if let monitor {
                NSEvent.removeMonitor(monitor)
                self.monitor = nil
            }
        }

        deinit {
            removeMonitor()
        }
    }
}
