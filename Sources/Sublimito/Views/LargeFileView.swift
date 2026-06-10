import SwiftUI
import AppKit

/// Visor de ficheros enormes: lee por ventanas con el fichero mapeado en memoria,
/// sin cargarlo entero jamás. Solo lectura, con búsqueda por streaming.
@MainActor
final class LargeFileModel: ObservableObject {
    let url: URL
    let fileSize: UInt64
    private var data: Data?

    static let windowSize = 1_000_000 // 1MB por ventana

    @Published var offset: UInt64 = 0
    @Published var text: String = ""
    @Published var query: String = ""
    @Published var status: String = ""

    init(url: URL, fileSize: UInt64) {
        self.url = url
        self.fileSize = fileSize
        data = try? Data(contentsOf: url, options: .alwaysMapped)
        if data == nil { status = "Could not open file" }
        refresh()
    }

    var fraction: Double {
        get { fileSize > 0 ? Double(offset) / Double(fileSize) : 0 }
        set { jump(to: UInt64(newValue * Double(fileSize))) }
    }

    func refresh() {
        guard let data, !data.isEmpty else { text = ""; return }
        var start = Int(min(offset, UInt64(data.count - 1)))
        // Alinear el arranque al principio de una línea (hasta 4KB hacia atrás)
        if start > 0 {
            let lookBehind = max(0, start - 4096)
            if let nl = data[lookBehind..<start].lastIndex(of: 0x0A) {
                start = nl + 1
            }
        }
        let end = min(data.count, start + Self.windowSize)
        text = String(decoding: data[start..<end], as: UTF8.self)
        offset = UInt64(start)
        let pct = fileSize > 0 ? Double(start) / Double(fileSize) * 100 : 0
        status = String(format: "%@ of %@ (%.1f%%)",
                        Self.format(UInt64(start)), Self.format(fileSize), pct)
    }

    func nextWindow() {
        jump(to: offset + UInt64(Self.windowSize))
    }

    func prevWindow() {
        jump(to: offset > UInt64(Self.windowSize) ? offset - UInt64(Self.windowSize) : 0)
    }

    func jump(to newOffset: UInt64) {
        offset = min(newOffset, fileSize > 0 ? fileSize - 1 : 0)
        refresh()
    }

    /// Busca la siguiente ocurrencia (case insensitive ASCII) desde la posición actual.
    func findNext() {
        guard let data, !query.isEmpty else { return }
        // Mismo folding (| 0x20) en needle y haystack para comparar simétrico
        let needle = Array(query.lowercased().utf8).map { $0 | 0x20 }
        guard !needle.isEmpty else { return }
        let from = Int(offset) + 1
        if let pos = Self.scan(data: data, needle: needle, from: from)
            ?? Self.scan(data: data, needle: needle, from: 0) { // vuelta al principio
            jump(to: UInt64(pos))
            status = "Match at \(Self.format(UInt64(pos)))  ·  " + status
        } else {
            status = "No matches  ·  " + status
        }
    }

    private static func scan(data: Data, needle: [UInt8], from: Int) -> Int? {
        let n = needle.count
        guard n > 0, from < data.count - n else { return nil }
        return data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) -> Int? in
            let bytes = raw.bindMemory(to: UInt8.self)
            let first = needle[0]
            var i = from
            let limit = bytes.count - n
            while i <= limit {
                let c = bytes[i] | 0x20 // tolower aproximado para ASCII
                if c == first {
                    var match = true
                    for j in 1..<n where (bytes[i + j] | 0x20) != needle[j] {
                        match = false
                        break
                    }
                    if match { return i }
                }
                i += 1
            }
            return nil
        }
    }

    static func format(_ bytes: UInt64) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }
}

struct LargeFileView: View {
    @ObservedObject var buffer: Buffer
    @StateObject private var model: LargeFileModel

    init(buffer: Buffer) {
        self.buffer = buffer
        _model = StateObject(wrappedValue: LargeFileModel(
            url: buffer.fileURL ?? URL(fileURLWithPath: "/dev/null"),
            fileSize: buffer.fileSize))
    }

    var body: some View {
        VStack(spacing: 0) {
            controls
            Divider()
            ReadOnlyTextView(text: model.text)
        }
    }

    private var controls: some View {
        HStack(spacing: 10) {
            Label("Large file (read-only)", systemImage: "doc.zipper")
                .foregroundStyle(.orange)
            Text(model.status)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Slider(value: Binding(get: { model.fraction }, set: { model.fraction = $0 }))
                .frame(maxWidth: 220)
            Button(action: { model.prevWindow() }) { Image(systemName: "chevron.left") }
                .help("Previous chunk")
            Button(action: { model.nextWindow() }) { Image(systemName: "chevron.right") }
                .help("Next chunk")
            TextField("Find…", text: $model.query)
                .textFieldStyle(.roundedBorder)
                .frame(width: 160)
                .onSubmit { model.findNext() }
            Button("Next") { model.findNext() }
        }
        .controlSize(.small)
        .font(.system(size: 11))
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

/// NSTextView de solo lectura para mostrar la ventana actual del fichero.
private struct ReadOnlyTextView: NSViewRepresentable {
    let text: String

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        let textView = scrollView.documentView as! NSTextView
        textView.isEditable = false
        textView.isRichText = false
        textView.usesFindBar = true
        textView.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        textView.textContainerInset = NSSize(width: 8, height: 8)
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        if textView.string != text {
            textView.string = text
            textView.scrollToBeginningOfDocument(nil)
        }
    }
}
