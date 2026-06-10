import SwiftUI
import AppKit

extension View {
    /// Cursor de mano al pasar por encima, para dejar claro que el elemento es clicable.
    func pointingHandCursor() -> some View {
        onHover { inside in
            if inside {
                NSCursor.pointingHand.push()
            } else {
                NSCursor.pop()
            }
        }
    }
}
