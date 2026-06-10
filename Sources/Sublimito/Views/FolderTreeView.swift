import SwiftUI

/// Árbol de ficheros de la carpeta abierta, con carga perezosa por nivel.
struct FolderTreeView: View {
    let root: URL
    @EnvironmentObject var state: AppState

    var body: some View {
        ForEach(FolderTreeView.children(of: root)) { node in
            FolderNodeView(node: node, depth: 0)
        }
    }

    struct FileNode: Identifiable {
        let url: URL
        let isDirectory: Bool
        var id: String { url.path }
        var name: String { url.lastPathComponent }
    }

    static func children(of url: URL) -> [FileNode] {
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]) else { return [] }
        return entries
            .map { FileNode(url: $0, isDirectory: (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false) }
            .sorted {
                if $0.isDirectory != $1.isDirectory { return $0.isDirectory }
                return $0.name.localizedStandardCompare($1.name) == .orderedAscending
            }
    }
}

private struct FolderNodeView: View {
    let node: FolderTreeView.FileNode
    let depth: Int
    @EnvironmentObject var state: AppState
    @State private var expanded = false
    @State private var children: [FolderTreeView.FileNode] = []

    var body: some View {
        if node.isDirectory {
            HStack(spacing: 4) {
                Image(systemName: expanded ? "chevron.down" : "chevron.right")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 10)
                Image(systemName: "folder")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.accentColor.opacity(0.8))
                Text(node.name).lineLimit(1)
                Spacer()
            }
            .padding(.leading, CGFloat(depth) * 12)
            .contentShape(Rectangle())
            .pointingHandCursor()
            .onTapGesture {
                expanded.toggle()
                if expanded { children = FolderTreeView.children(of: node.url) }
            }
            if expanded {
                ForEach(children) { child in
                    FolderNodeView(node: child, depth: depth + 1)
                }
            }
        } else {
            HStack(spacing: 4) {
                Spacer().frame(width: 10)
                Image(systemName: "doc.text")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Text(node.name).lineLimit(1)
                Spacer()
            }
            .padding(.leading, CGFloat(depth) * 12)
            .contentShape(Rectangle())
            .pointingHandCursor()
            .onTapGesture { state.open(url: node.url) }
            .contextMenu {
                Button("Open") { state.open(url: node.url) }
                Button("Show in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([node.url])
                }
            }
        }
    }
}
