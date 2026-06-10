import SwiftUI
import AppKit

/// Visor de ficheros enormes: lee por ventanas con el fichero mapeado en memoria,
/// sin cargarlo entero jamás. Solo lectura. Una única barra de búsqueda (abajo)
/// que busca en el fichero completo por streaming y resalta lo visible.
@MainActor
final class LargeFileModel: ObservableObject {
    let url: URL
    let fileSize: UInt64
    private var data: Data?

    static let windowSize = 1_000_000 // 1MB por ventana

    @Published var offset: UInt64 = 0
    @Published var text: String = ""
    @Published var query: String = "" {
        didSet {
            recomputeWindowMatches()
            scheduleGlobalCount()
        }
    }
    @Published var globalCount: Int?
    @Published var counting = false
    private var countTask: Task<Void, Never>?
    @Published var status: String = ""
    @Published var searching = false
    @Published var windowMatches: [NSRange] = []
    @Published var currentMatch: Int?

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

    var matchCounter: String {
        guard !query.isEmpty else { return "" }
        var parts: [String] = []
        if windowMatches.isEmpty {
            parts.append("0 in view")
        } else {
            parts.append("\((currentMatch ?? 0) + 1) of \(windowMatches.count) in view")
        }
        if let total = globalCount {
            parts.append("\(Self.formatCount(total)) in file")
        }
        return parts.joined(separator: "  ·  ")
    }

    static func formatCount(_ n: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: n)) ?? "\(n)"
    }

    func refresh(selectNearByte: Int? = nil) {
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
        var nearUTF16: Int?
        if let byte = selectNearByte, byte >= start, byte <= end {
            nearUTF16 = String(decoding: data[start..<byte], as: UTF8.self).utf16.count
        }
        recomputeWindowMatches(selectNear: nearUTF16)
    }

    func nextWindow() { jump(to: offset + UInt64(Self.windowSize)) }
    func prevWindow() { jump(to: offset > UInt64(Self.windowSize) ? offset - UInt64(Self.windowSize) : 0) }

    func jump(to newOffset: UInt64, selectNearByte: Int? = nil) {
        offset = min(newOffset, fileSize > 0 ? fileSize - 1 : 0)
        refresh(selectNearByte: selectNearByte)
    }

    // MARK: - Búsqueda

    private func recomputeWindowMatches(selectNear utf16Pos: Int? = nil) {
        windowMatches = []
        currentMatch = nil
        guard !query.isEmpty else { return }
        let ns = text as NSString
        var location = 0
        while location < ns.length && windowMatches.count < 5000 {
            let found = ns.range(of: query, options: .caseInsensitive,
                                 range: NSRange(location: location, length: ns.length - location))
            if found.location == NSNotFound { break }
            windowMatches.append(found)
            location = found.location + max(found.length, 1)
        }
        guard !windowMatches.isEmpty else { return }
        if let pos = utf16Pos {
            currentMatch = windowMatches.firstIndex { $0.location >= pos } ?? 0
        } else {
            currentMatch = 0
        }
    }

    /// Cuenta todas las ocurrencias del fichero completo en background.
    private func scheduleGlobalCount() {
        countTask?.cancel()
        globalCount = nil
        guard !query.isEmpty, let data else { counting = false; return }
        counting = true
        let needle = Array(query.lowercased().utf8).map { $0 | 0x20 }
        countTask = Task.detached(priority: .utility) { [weak self] in
            try? await Task.sleep(nanoseconds: 500_000_000) // debounce mientras escribe
            if Task.isCancelled { return }
            let total = Self.countOccurrences(data: data, needle: needle)
            if Task.isCancelled { return }
            await MainActor.run { [weak self] in
                guard let self, !Task.isCancelled else { return }
                self.globalCount = total
                self.counting = false
            }
        }
    }

    /// Escaneo completo con memchr sobre el primer byte (rápido para GB).
    nonisolated private static func countOccurrences(data: Data, needle: [UInt8]) -> Int? {
        let n = needle.count
        guard n > 0, data.count >= n else { return 0 }
        return data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) -> Int? in
            guard let base = raw.baseAddress else { return 0 }
            let bytes = raw.bindMemory(to: UInt8.self)
            let limit = raw.count - n
            let lower = needle[0]
            // Ambas variantes del byte plegado (cubre letras y símbolos como @ vs `)
            let upper = lower & ~0x20
            var count = 0
            var i = 0
            var lastCancelCheck = 0
            while i <= limit {
                // Candidato más cercano del primer byte (variantes mayúscula y minúscula)
                let remaining = raw.count - i
                let posLower = memchr(base + i, Int32(lower), remaining)
                let posUpper = memchr(base + i, Int32(upper), remaining)
                var candidate: Int
                switch (posLower, posUpper) {
                case (nil, nil): return count
                case (let l?, nil): candidate = base.distance(to: UnsafeRawPointer(l))
                case (nil, let u?): candidate = base.distance(to: UnsafeRawPointer(u))
                case (let l?, let u?):
                    candidate = min(base.distance(to: UnsafeRawPointer(l)),
                                    base.distance(to: UnsafeRawPointer(u)))
                }
                if candidate > limit { return count }
                var match = true
                for j in 1..<n where (bytes[candidate + j] | 0x20) != needle[j] {
                    match = false
                    break
                }
                if match {
                    count += 1
                    i = candidate + n
                } else {
                    i = candidate + 1
                }
                if i - lastCancelCheck > 8_000_000 {
                    lastCancelCheck = i
                    if Task.isCancelled { return nil }
                }
            }
            return count
        }
    }

    /// Siguiente ocurrencia: primero dentro de la ventana, si no, escaneo global en background.
    func findNext() {
        guard !query.isEmpty else { return }
        if let current = currentMatch, current + 1 < windowMatches.count {
            currentMatch = current + 1
            return
        }
        globalScan(forward: true)
    }

    func findPrev() {
        guard !query.isEmpty else { return }
        if let current = currentMatch, current > 0 {
            currentMatch = current - 1
            return
        }
        globalScan(forward: false)
    }

    private func globalScan(forward: Bool) {
        guard let data, !searching else { return }
        let needle = Array(query.lowercased().utf8).map { $0 | 0x20 }
        guard !needle.isEmpty else { return }
        let windowStart = Int(offset)
        let windowEnd = min(data.count, windowStart + Self.windowSize)
        searching = true
        status = "Searching…"
        Task.detached(priority: .userInitiated) { [weak self] in
            var pos: Int?
            if forward {
                pos = Self.scan(data: data, needle: needle, from: windowEnd, forward: true)
                    ?? Self.scan(data: data, needle: needle, from: 0, forward: true) // wrap
            } else {
                pos = Self.scan(data: data, needle: needle, from: windowStart - 1, forward: false)
                    ?? Self.scan(data: data, needle: needle, from: data.count - 1, forward: false) // wrap
            }
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.searching = false
                if let pos {
                    self.jump(to: UInt64(pos), selectNearByte: pos)
                    if !forward, !self.windowMatches.isEmpty {
                        // Al ir hacia atrás, selecciona la coincidencia encontrada, no la primera
                        let target = self.currentMatch ?? 0
                        self.currentMatch = max(0, min(target, self.windowMatches.count - 1))
                    }
                } else {
                    self.status = "No matches  ·  " + self.status
                }
            }
        }
    }

    nonisolated private static func scan(data: Data, needle: [UInt8], from: Int, forward: Bool) -> Int? {
        let n = needle.count
        guard n > 0, data.count >= n else { return nil }
        return data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) -> Int? in
            let bytes = raw.bindMemory(to: UInt8.self)
            let limit = bytes.count - n
            let first = needle[0]

            func matches(at i: Int) -> Bool {
                if (bytes[i] | 0x20) != first { return false }
                for j in 1..<n where (bytes[i + j] | 0x20) != needle[j] { return false }
                return true
            }

            if forward {
                var i = max(0, from)
                while i <= limit {
                    if matches(at: i) { return i }
                    i += 1
                }
            } else {
                var i = min(from, limit)
                while i >= 0 {
                    if matches(at: i) { return i }
                    i -= 1
                }
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
    @EnvironmentObject var state: AppState
    @StateObject private var model: LargeFileModel
    @FocusState private var searchFocused: Bool

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
            LargeFileTextView(text: model.text,
                              matches: model.windowMatches,
                              currentMatch: model.currentMatch)
            Divider()
            searchBar
        }
        .onChange(of: state.largeFileFindRequest) { _, _ in
            searchFocused = true
        }
    }

    private var controls: some View {
        HStack(spacing: 10) {
            Label("Large file (read-only)", systemImage: "doc.zipper")
                .foregroundStyle(.orange)
            Text(model.status)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            if model.searching { ProgressView().controlSize(.mini) }
            Slider(value: Binding(get: { model.fraction }, set: { model.fraction = $0 }))
                .frame(maxWidth: 220)
            Button(action: { model.prevWindow() }) { Image(systemName: "chevron.left") }
                .help("Previous chunk")
            Button(action: { model.nextWindow() }) { Image(systemName: "chevron.right") }
                .help("Next chunk")
        }
        .controlSize(.small)
        .font(.system(size: 11))
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Find in whole file…", text: $model.query)
                .textFieldStyle(.plain)
                .focused($searchFocused)
                .onSubmit { model.findNext() }
            if !model.query.isEmpty {
                Text(model.matchCounter)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                if model.counting {
                    ProgressView().controlSize(.mini)
                        .help("Counting occurrences in the whole file…")
                }
            }
            Button(action: { model.findPrev() }) { Image(systemName: "chevron.up") }
                .help("Previous match (whole file)")
            Button(action: { model.findNext() }) { Image(systemName: "chevron.down") }
                .help("Next match (whole file)")
                .keyboardShortcut("g", modifiers: .command)
        }
        .controlSize(.small)
        .font(.system(size: 12))
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

/// NSTextView de solo lectura con resaltado de coincidencias.
private struct LargeFileTextView: NSViewRepresentable {
    let text: String
    let matches: [NSRange]
    let currentMatch: Int?

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        let textView = scrollView.documentView as! NSTextView
        textView.isEditable = false
        textView.isRichText = false
        textView.usesFindBar = false
        textView.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        textView.textContainerInset = NSSize(width: 8, height: 8)
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView,
              let storage = textView.textStorage else { return }
        if textView.string != text {
            textView.string = text
            textView.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
            textView.scrollToBeginningOfDocument(nil)
        }
        let full = NSRange(location: 0, length: storage.length)
        storage.removeAttribute(.backgroundColor, range: full)
        for range in matches where NSMaxRange(range) <= storage.length {
            storage.addAttribute(.backgroundColor,
                                 value: NSColor.systemYellow.withAlphaComponent(0.30),
                                 range: range)
        }
        if let index = currentMatch, index < matches.count, NSMaxRange(matches[index]) <= storage.length {
            let range = matches[index]
            storage.addAttribute(.backgroundColor,
                                 value: NSColor.systemOrange.withAlphaComponent(0.75),
                                 range: range)
            textView.scrollRangeToVisible(range)
        }
    }
}
