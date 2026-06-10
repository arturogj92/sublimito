import SwiftUI

/// Find in Files: busca en pestañas abiertas, en recientes o en la carpeta del
/// proyecto, con toggle de ámbito y soporte de regex.
struct FindInFilesView: View {
    @EnvironmentObject var state: AppState
    @State private var query = ""
    @State private var scope: Scope = .open
    @State private var useRegex = false
    @State private var results: [Result] = []
    @State private var searching = false
    @State private var searchTask: Task<Void, Never>?
    @FocusState private var focused: Bool

    enum Scope: String, CaseIterable, Identifiable {
        case open = "Open Tabs"
        case folder = "Folder"
        case everything = "Everything"
        var id: String { rawValue }
    }

    struct Result: Identifiable {
        let id = UUID()
        let fileName: String
        let location: Location
        let line: Int
        let snippet: String
        let range: NSRange

        enum Location {
            case buffer(UUID)
            case file(URL)
        }
    }

    var body: some View {
        ZStack(alignment: .top) {
            Color.black.opacity(0.15)
                .ignoresSafeArea()
                .onTapGesture { state.findInFilesShown = false }
            panel
                .padding(.top, 50)
        }
    }

    private var panel: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "text.magnifyingglass").foregroundStyle(.secondary)
                TextField("Find in files…", text: $query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 15))
                    .focused($focused)
                    .onSubmit { runSearch() }
                    .onKeyPress(.escape) { state.findInFilesShown = false; return .handled }
                Toggle(".*", isOn: $useRegex)
                    .toggleStyle(.button)
                    .help("Regular expression")
                Picker("", selection: $scope) {
                    ForEach(Scope.allCases) { s in
                        Text(s.rawValue).tag(s)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 260)
                Button("Search") { runSearch() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(12)
            Divider()
            if searching {
                ProgressView().controlSize(.small).padding(16)
            } else if results.isEmpty {
                Text(query.isEmpty ? "Type a query and press Enter" : "No results")
                    .foregroundStyle(.secondary)
                    .padding(16)
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(results) { result in
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Text(result.fileName)
                                    .font(.system(size: 11, weight: .semibold))
                                    .frame(width: 190, alignment: .leading)
                                    .lineLimit(1)
                                Text("\(result.line)")
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundStyle(.tertiary)
                                    .frame(width: 40, alignment: .trailing)
                                Text(result.snippet)
                                    .font(.system(size: 11, design: .monospaced))
                                    .lineLimit(1)
                                Spacer()
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 4)
                            .contentShape(Rectangle())
                            .pointingHandCursor()
                            .onTapGesture { open(result) }
                            Divider().opacity(0.3)
                        }
                    }
                }
                .frame(maxHeight: 420)
                HStack {
                    Text("\(results.count) matches\(results.count >= 500 ? " (capped)" : "")")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
            }
        }
        .frame(width: 720)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.separator, lineWidth: 1))
        .shadow(radius: 24, y: 8)
        .onAppear { focused = true }
    }

    private func open(_ result: Result) {
        switch result.location {
        case .buffer(let id):
            if let buffer = state.buffers.first(where: { $0.id == id }) {
                buffer.isPreview = false
                state.activeID = id
                state.pendingSelection = .init(bufferID: id, range: result.range)
            }
        case .file(let url):
            state.open(url: url)
            if let buffer = state.buffers.first(where: { $0.fileURL?.path == url.path }) {
                buffer.isPreview = false
                state.pendingSelection = .init(bufferID: buffer.id, range: result.range)
            }
        }
        state.findInFilesShown = false
    }

    private func runSearch() {
        guard !query.isEmpty else { return }
        searchTask?.cancel()
        searching = true
        results = []

        // Snapshot en el main actor de todo lo que necesita el background
        let q = query
        let regex = useRegex
        let currentScope = scope
        let openBuffers: [(UUID, String, String)] = state.buffers
            .filter { !$0.isLargeFile }
            .map { ($0.id, $0.name, $0.content) }
        let folder = state.folderURL
        let recentPaths: [String] = state.recents.compactMap(\.path)
        let openPaths = Set(state.buffers.compactMap { $0.fileURL?.path })

        searchTask = Task.detached(priority: .userInitiated) {
            var found: [Result] = []
            let matcher = Matcher(query: q, regex: regex)

            func searchText(_ text: String, fileName: String, location: Result.Location) {
                guard found.count < 500 else { return }
                found.append(contentsOf: matcher.matches(in: text, fileName: fileName,
                                                         location: location, limit: 500 - found.count))
            }

            if currentScope == .open || currentScope == .everything {
                for (id, name, content) in openBuffers {
                    searchText(content, fileName: name, location: .buffer(id))
                }
            }
            if currentScope == .everything {
                for path in recentPaths where !openPaths.contains(path) {
                    guard found.count < 500 else { break }
                    let url = URL(fileURLWithPath: path)
                    if let text = Self.readSearchableFile(url) {
                        searchText(text, fileName: url.lastPathComponent, location: .file(url))
                    }
                }
            }
            if currentScope == .folder || currentScope == .everything, let folder {
                let walker = FileManager.default.enumerator(at: folder,
                                                            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
                                                            options: [.skipsHiddenFiles, .skipsPackageDescendants])
                while let item = walker?.nextObject() as? URL {
                    if Task.isCancelled || found.count >= 500 { break }
                    guard (try? item.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else { continue }
                    if openPaths.contains(item.path) { continue } // ya buscado en memoria
                    if let text = Self.readSearchableFile(item) {
                        searchText(text, fileName: item.lastPathComponent, location: .file(item))
                    }
                }
            }

            let finalResults = found
            await MainActor.run {
                results = finalResults
                searching = false
            }
        }
    }

    /// Lee ficheros de texto razonables (max 2MB, descarta binarios por byte nulo).
    nonisolated private static func readSearchableFile(_ url: URL) -> String? {
        guard let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize,
              size > 0, size <= 2_000_000 else { return nil }
        guard let data = try? Data(contentsOf: url) else { return nil }
        if data.prefix(8192).contains(0) { return nil } // binario
        return String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1)
    }

    private struct Matcher {
        let query: String
        let regexObject: NSRegularExpression?

        init(query: String, regex: Bool) {
            self.query = query
            regexObject = regex
                ? try? NSRegularExpression(pattern: query, options: [.caseInsensitive])
                : nil
        }

        func matches(in text: String, fileName: String,
                     location: FindInFilesView.Result.Location, limit: Int) -> [FindInFilesView.Result] {
            guard limit > 0 else { return [] }
            var out: [FindInFilesView.Result] = []
            let ns = text as NSString
            var pos = 0
            var lineNo = 0
            while pos < ns.length && out.count < limit {
                let lineRange = ns.lineRange(for: NSRange(location: pos, length: 0))
                lineNo += 1
                let line = ns.substring(with: lineRange)
                var matchRange = NSRange(location: NSNotFound, length: 0)
                if let regexObject {
                    if let m = regexObject.firstMatch(in: line, range: NSRange(location: 0, length: (line as NSString).length)) {
                        matchRange = m.range
                    }
                } else {
                    matchRange = (line as NSString).range(of: query, options: .caseInsensitive)
                }
                if matchRange.location != NSNotFound {
                    let snippet = line.trimmingCharacters(in: .whitespacesAndNewlines).prefix(120)
                    out.append(FindInFilesView.Result(
                        fileName: fileName, location: location, line: lineNo,
                        snippet: String(snippet),
                        range: NSRange(location: lineRange.location + matchRange.location,
                                       length: max(matchRange.length, 1))))
                }
                let next = NSMaxRange(lineRange)
                if next <= pos { break }
                pos = next
            }
            return out
        }
    }
}
