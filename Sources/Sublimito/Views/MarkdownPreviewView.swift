import SwiftUI
import WebKit

struct MarkdownPreviewView: NSViewRepresentable {
    @ObservedObject var buffer: Buffer

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        let webView = FileDropWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.setValue(false, forKey: "drawsBackground") // deja que mande el CSS
        context.coordinator.webView = webView
        webView.loadHTMLString(Self.template, baseURL: nil)
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        context.coordinator.render(buffer.content)
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        weak var webView: WKWebView?
        private var isLoaded = false
        private var pending: String?
        private var lastRendered: String?

        func render(_ markdown: String) {
            guard markdown != lastRendered else { return }
            guard isLoaded, let webView else {
                pending = markdown
                return
            }
            lastRendered = markdown
            guard let data = try? JSONEncoder().encode([markdown]),
                  let json = String(data: data, encoding: .utf8) else { return }
            webView.evaluateJavaScript("window.renderMarkdown((\(json))[0]);", completionHandler: nil)
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            isLoaded = true
            if let pending {
                self.pending = nil
                render(pending)
            }
        }

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            if navigationAction.navigationType == .linkActivated, let url = navigationAction.request.url {
                NSWorkspace.shared.open(url)
                decisionHandler(.cancel)
                return
            }
            decisionHandler(.allow)
        }
    }

    static let template: String = {
        let css = loadResource("github-markdown", ext: "css")
        let js = loadResource("marked.min", ext: "js")
        return """
        <!doctype html>
        <html>
        <head>
        <meta charset="utf-8">
        <style>\(css)</style>
        <style>
        html, body { margin: 0; padding: 0; }
        body { background: var(--bgColor-default, #ffffff); }
        @media (prefers-color-scheme: dark) { body { background: #0d1117; } }
        .markdown-body { box-sizing: border-box; min-width: 200px; max-width: 880px;
                         margin: 0 auto; padding: 28px 32px 60px; }
        </style>
        <script>\(js)</script>
        </head>
        <body>
        <article id="content" class="markdown-body"></article>
        <script>
        marked.setOptions({ gfm: true, breaks: false });
        window.renderMarkdown = function(md) {
            document.getElementById('content').innerHTML = marked.parse(md);
        };
        </script>
        </body>
        </html>
        """
    }()

    private static func loadResource(_ name: String, ext: String) -> String {
        guard let url = Bundle.main.url(forResource: name, withExtension: ext),
              let text = try? String(contentsOf: url, encoding: .utf8) else { return "" }
        return text
    }
}
