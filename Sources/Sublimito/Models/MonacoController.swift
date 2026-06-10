import Foundation
import WebKit
import AppKit

/// Controlador único del editor Monaco embebido. La WKWebView vive durante toda la
/// sesión (un modelo por buffer mantiene la pila de undo de cada pestaña) y las
/// pestañas se cambian con api.openBuffer en lugar de recrear la vista.
@MainActor
final class MonacoController: NSObject, WKScriptMessageHandlerWithReply, WKNavigationDelegate {
    static let shared = MonacoController()

    let webView: WKWebView
    private var ready = false
    private var pendingCalls: [String] = []
    private(set) var currentBufferID: UUID?
    /// Último contenido conocido por Monaco de cada buffer, para no reenviar
    /// por el bridge el texto completo en cada actualización de SwiftUI.
    private var lastMonacoText: [UUID: String] = [:]

    override private init() {
        let config = WKWebViewConfiguration()
        webView = WKWebView(frame: .zero, configuration: config)
        super.init()
        config.userContentController.addScriptMessageHandler(self, contentWorld: .page, name: "bridge")
        webView.navigationDelegate = self
        webView.setValue(false, forKey: "drawsBackground")
        if let root = Bundle.main.resourceURL?.appendingPathComponent("monaco", isDirectory: true) {
            let index = root.appendingPathComponent("index.html")
            webView.loadFileURL(index, allowingReadAccessTo: root)
        }
    }

    // MARK: - Llamadas hacia Monaco

    private func call(_ js: String) {
        if ready {
            webView.evaluateJavaScript(js, completionHandler: nil)
        } else {
            pendingCalls.append(js)
        }
    }

    private static func json(_ value: String) -> String {
        guard let data = try? JSONEncoder().encode([value]),
              let text = String(data: data, encoding: .utf8) else { return "\"\"" }
        return "(\(text))[0]"
    }

    func show(_ buffer: Buffer) {
        guard currentBufferID != buffer.id else {
            syncText(buffer)
            return
        }
        currentBufferID = buffer.id
        lastMonacoText[buffer.id] = buffer.content
        call("api.openBuffer(\(Self.json(buffer.id.uuidString)), \(Self.json(buffer.name)), \(Self.json(buffer.content)));")
    }

    /// Propaga a Monaco contenido cambiado desde fuera (recargas externas, restore).
    func syncText(_ buffer: Buffer) {
        guard lastMonacoText[buffer.id] != buffer.content else { return }
        lastMonacoText[buffer.id] = buffer.content
        call("api.setText(\(Self.json(buffer.id.uuidString)), \(Self.json(buffer.content)));")
    }

    func closeBuffer(_ id: UUID) {
        if currentBufferID == id { currentBufferID = nil }
        lastMonacoText.removeValue(forKey: id)
        call("api.closeBuffer(\(Self.json(id.uuidString)));")
    }

    func applySettings(fontSize: CGFloat, wordWrap: Bool, lineNumbers: Bool, minimap: Bool) {
        let opts = """
        {"fontSize": \(Int(fontSize)), "wordWrap": "\(wordWrap ? "on" : "off")", \
        "lineNumbers": "\(lineNumbers ? "on" : "off")", "minimap": {"enabled": \(minimap)}}
        """
        call("api.setOptions(\(opts));")
    }

    func goTo(offset: Int, length: Int) {
        call("api.gotoOffset(\(offset), \(length));")
    }

    func focus() { call("api.focus();") }

    enum FindCommand { case find, findReplace, findNext, findPrev }
    func runFind(_ command: FindCommand) {
        switch command {
        case .find: call("api.find();")
        case .findReplace: call("api.findReplace();")
        case .findNext: call("api.findNext();")
        case .findPrev: call("api.findPrev();")
        }
        webView.window?.makeFirstResponder(webView)
    }

    /// Vuelca el cambio pendiente del debounce (llamar antes de guardar o cerrar).
    func flushPendingEdits() {
        call("api.flushPending();")
    }

    // MARK: - Mensajes desde Monaco

    func userContentController(_ userContentController: WKUserContentController,
                               didReceive message: WKScriptMessage) async -> (Any?, String?) {
        guard let body = message.body as? [String: Any], let type = body["type"] as? String else {
            return (nil, nil)
        }
        switch type {
        case "ready":
            ready = true
            let queued = pendingCalls
            pendingCalls = []
            for js in queued { webView.evaluateJavaScript(js, completionHandler: nil) }
        case "change":
            if let idString = body["id"] as? String, let id = UUID(uuidString: idString),
               let text = body["text"] as? String,
               let buffer = AppState.shared.buffers.first(where: { $0.id == id }) {
                lastMonacoText[id] = text
                guard buffer.content != text else { break }
                buffer.suppressChangeNotifications = true
                buffer.content = text
                buffer.suppressChangeNotifications = false
                AppState.shared.bufferEdited(buffer)
            }
        default:
            break
        }
        return (nil, nil)
    }
}
