import SwiftUI

struct QuickOpenView: View {
    @EnvironmentObject var state: AppState
    @State private var query = ""
    @State private var selection = 0
    @FocusState private var focused: Bool

    private struct Item: Identifiable {
        enum Target {
            case buffer(Buffer)
            case recent(RecentEntry)
            case bufferLine(Buffer, NSRange)
            case recentLine(RecentEntry)
        }
        let id: String
        let title: String
        let subtitle: String
        let icon: String
        let target: Target
        let score: Int
    }

    private struct ContentMatch {
        let line: Int
        let snippet: String
        let range: NSRange
    }

    private var items: [Item] {
        var result: [Item] = []

        // Por nombre: pestañas abiertas.
        for buffer in state.orderedTabs {
            if let score = FuzzyMatcher.score(pattern: query, in: buffer.name) {
                result.append(Item(id: "buf-\(buffer.id)", title: buffer.name,
                                   subtitle: buffer.fileURL?.path ?? "Open tab",
                                   icon: buffer.isPinned ? "pin.fill" : "doc.text",
                                   target: .buffer(buffer), score: score + 100))
            }
        }
        // Por nombre: recientes.
        for entry in state.visibleRecents {
            let candidate = entry.name + " " + (entry.path ?? "")
            if let score = FuzzyMatcher.score(pattern: query, in: candidate) {
                result.append(Item(id: "rec-\(entry.id)", title: entry.name,
                                   subtitle: entry.path ?? "Unsaved note (recent)",
                                   icon: "clock", target: .recent(entry), score: score + 50))
            }
        }
        // Por contenido (a partir de 2 caracteres).
        if query.count >= 2 {
            for buffer in state.orderedTabs {
                for match in Self.contentMatches(in: buffer.content, query: query, limit: 3) {
                    result.append(Item(id: "line-\(buffer.id)-\(match.range.location)",
                                       title: "\(buffer.name)  ·  line \(match.line)",
                                       subtitle: match.snippet,
                                       icon: "text.magnifyingglass",
                                       target: .bufferLine(buffer, match.range), score: 20))
                }
            }
            for entry in state.visibleRecents.prefix(15) {
                guard let content = Self.recentContent(entry) else { continue }
                for match in Self.contentMatches(in: content, query: query, limit: 2) {
                    result.append(Item(id: "recline-\(entry.id)-\(match.range.location)",
                                       title: "\(entry.name)  ·  line \(match.line)",
                                       subtitle: match.snippet,
                                       icon: "text.magnifyingglass",
                                       target: .recentLine(entry), score: 10))
                }
            }
        }
        return result.sorted { $0.score > $1.score }
    }

    private static func recentContent(_ entry: RecentEntry) -> String? {
        if let path = entry.path {
            let url = URL(fileURLWithPath: path)
            if let size = try? FileManager.default.attributesOfItem(atPath: path)[.size] as? Int,
               size > 1_000_000 { return nil } // no escanear ficheros enormes en cada pulsación
            return AppState.readText(at: url)
        }
        if let dID = entry.draftID {
            return AppState.readText(at: AppState.draftsDirectory.appendingPathComponent(dID.uuidString + ".txt"))
        }
        return nil
    }

    private static func contentMatches(in content: String, query: String, limit: Int) -> [ContentMatch] {
        var matches: [ContentMatch] = []
        let ns = content as NSString
        var pos = 0
        var lineNo = 0
        while pos < ns.length && matches.count < limit {
            let lineRange = ns.lineRange(for: NSRange(location: pos, length: 0))
            lineNo += 1
            let line = ns.substring(with: lineRange) as NSString
            let found = line.range(of: query, options: .caseInsensitive)
            if found.location != NSNotFound {
                let snippet = (line as String)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .prefix(90)
                matches.append(ContentMatch(line: lineNo, snippet: String(snippet),
                                            range: NSRange(location: lineRange.location + found.location,
                                                           length: found.length)))
            }
            let next = NSMaxRange(lineRange)
            if next <= pos { break }
            pos = next
        }
        return matches
    }

    var body: some View {
        ZStack(alignment: .top) {
            Color.black.opacity(0.15)
                .ignoresSafeArea()
                .onTapGesture { dismiss() }
            panel
                .padding(.top, 60)
        }
    }

    private var panel: some View {
        let list = items
        return VStack(spacing: 0) {
            TextField("Search tabs, recents or content…", text: $query)
                .textFieldStyle(.plain)
                .font(.system(size: 16))
                .padding(12)
                .focused($focused)
                .onSubmit { openSelected(in: list) }
                .onKeyPress(.downArrow) {
                    selection = min(selection + 1, max(0, min(list.count, 14) - 1)); return .handled
                }
                .onKeyPress(.upArrow) {
                    selection = max(selection - 1, 0); return .handled
                }
                .onKeyPress(.escape) { dismiss(); return .handled }
            Divider()
            if list.isEmpty {
                Text("No results")
                    .foregroundStyle(.secondary)
                    .padding(16)
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(Array(list.prefix(14).enumerated()), id: \.element.id) { index, item in
                            HStack(spacing: 8) {
                                Image(systemName: item.icon)
                                    .foregroundStyle(.secondary)
                                    .frame(width: 16)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(item.title).lineLimit(1)
                                    Text(item.subtitle)
                                        .font(.system(size: 10))
                                        .foregroundStyle(.tertiary)
                                        .lineLimit(1)
                                        .truncationMode(item.subtitle.hasPrefix("/") ? .head : .tail)
                                }
                                Spacer()
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(index == selection ? Color.accentColor.opacity(0.22) : Color.clear)
                            .contentShape(Rectangle())
                            .onTapGesture { open(item) }
                        }
                    }
                }
                .frame(maxHeight: 380)
            }
        }
        .frame(width: 600)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.separator, lineWidth: 1))
        .shadow(radius: 24, y: 8)
        .onAppear { focused = true; selection = 0 }
        .onChange(of: query) { _, _ in selection = 0 }
    }

    private func openSelected(in list: [Item]) {
        guard !list.isEmpty else { return }
        open(list[min(selection, min(list.count, 14) - 1)])
    }

    private func open(_ item: Item) {
        switch item.target {
        case .buffer(let buffer):
            state.activeID = buffer.id
        case .recent(let entry):
            state.reopenRecent(entry)
        case .bufferLine(let buffer, let range):
            buffer.isPreview = false
            state.activeID = buffer.id
            state.pendingSelection = .init(bufferID: buffer.id, range: range)
        case .recentLine(let entry):
            let q = query
            state.reopenRecent(entry)
            // Localiza el buffer recién abierto y salta a la primera coincidencia.
            let target: Buffer?
            if let path = entry.path {
                target = state.buffers.first { $0.fileURL?.path == path }
            } else {
                target = state.buffers.first { $0.id == entry.draftID }
            }
            if let target {
                target.isPreview = false
                let found = (target.content as NSString).range(of: q, options: .caseInsensitive)
                if found.location != NSNotFound {
                    state.pendingSelection = .init(bufferID: target.id, range: found)
                }
            }
        }
        dismiss()
    }

    private func dismiss() {
        state.quickOpenShown = false
    }
}
