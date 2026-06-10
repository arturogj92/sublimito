import SwiftUI

struct SidebarView: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        let pinned = state.orderedTabs.filter(\.isPinned)
        let unpinned = state.orderedTabs.filter { !$0.isPinned }
        List {
            if !pinned.isEmpty {
                Section("Fijados") {
                    ForEach(pinned) { buffer in
                        OpenBufferRow(buffer: buffer)
                    }
                }
            }
            Section("Abiertos") {
                ForEach(unpinned) { buffer in
                    OpenBufferRow(buffer: buffer)
                }
            }
            if !state.visibleRecents.isEmpty {
                Section("Recientes") {
                    ForEach(state.visibleRecents) { entry in
                        RecentRow(entry: entry)
                    }
                }
            }
        }
        .listStyle(.sidebar)
    }
}

private struct OpenBufferRow: View {
    @ObservedObject var buffer: Buffer
    @EnvironmentObject var state: AppState
    @State private var draftName = ""
    @FocusState private var nameFieldFocused: Bool

    var isActive: Bool { state.activeID == buffer.id }

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: buffer.isPinned ? "pin.fill" : (buffer.fileURL == nil ? "note.text" : "doc.text"))
                .foregroundStyle(buffer.isPinned ? Color.orange : Color.secondary)
                .font(.system(size: 11))
                .frame(width: 14)
            if state.renamingID == buffer.id {
                TextField("Nombre", text: $draftName)
                    .textFieldStyle(.plain)
                    .focused($nameFieldFocused)
                    .onSubmit { state.rename(buffer, to: draftName) }
                    .onExitCommand { state.renamingID = nil }
                    .onAppear {
                        draftName = buffer.name
                        nameFieldFocused = true
                    }
            } else {
                Text(buffer.name)
                    .lineLimit(1)
                    .fontWeight(isActive ? .semibold : .regular)
            }
            Spacer()
            if buffer.isDirty {
                Circle().fill(Color.secondary).frame(width: 6, height: 6)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { state.activeID = buffer.id }
        .overlay(MiddleClickCatcher { state.close(buffer) })
        .listRowBackground(isActive ? Color.accentColor.opacity(0.18) : Color.clear)
        .contextMenu {
            Button(buffer.isPinned ? "Desfijar" : "Fijar") { state.togglePin(buffer) }
            Button("Renombrar") { state.renamingID = buffer.id }
            Button("Guardar") { state.save(buffer) }
            if buffer.fileURL != nil || FileManager.default.fileExists(atPath: buffer.draftURL.path) {
                Button("Mostrar en Finder") { state.showInFinder(buffer) }
            }
            Divider()
            Button("Cerrar pestaña") { state.close(buffer) }
        }
    }
}

private struct RecentRow: View {
    let entry: RecentEntry
    @EnvironmentObject var state: AppState

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: entry.kind == .draft ? "note.text" : "clock")
                .foregroundStyle(Color.secondary)
                .font(.system(size: 11))
                .frame(width: 14)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    Text(entry.name).lineLimit(1)
                    if entry.draftID != nil && entry.kind == .file {
                        Circle().fill(Color.orange.opacity(0.8)).frame(width: 5, height: 5)
                    }
                }
                if let path = entry.path {
                    Text((path as NSString).deletingLastPathComponent)
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .truncationMode(.head)
                } else {
                    Text("Nota sin guardar")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }
            }
            Spacer()
        }
        .contentShape(Rectangle())
        .onTapGesture { state.reopenRecent(entry) }
        .contextMenu {
            Button("Abrir") { state.reopenRecent(entry) }
            Button("Eliminar de recientes") { state.removeRecent(entry) }
        }
    }
}
