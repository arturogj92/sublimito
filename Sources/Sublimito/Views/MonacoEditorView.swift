import SwiftUI
import WebKit

struct MonacoEditorView: NSViewRepresentable {
    @ObservedObject var buffer: Buffer
    @EnvironmentObject var state: AppState

    func makeNSView(context: Context) -> WKWebView {
        MonacoController.shared.webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        let controller = MonacoController.shared
        controller.show(buffer)
        controller.applySettings(fontSize: state.fontSize, wordWrap: state.wordWrap,
                                 lineNumbers: state.showLineNumbers, minimap: state.minimapVisible)
        if let pending = state.pendingSelection, pending.bufferID == buffer.id {
            controller.goTo(offset: pending.range.location, length: pending.range.length)
            DispatchQueue.main.async {
                AppState.shared.pendingSelection = nil
            }
        }
    }
}
