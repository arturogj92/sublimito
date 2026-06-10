import SwiftUI

struct SidebarView: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        let pinned = state.orderedTabs.filter(\.isPinned)
        let unpinned = state.orderedTabs.filter { !$0.isPinned }
        List {
            if !pinned.isEmpty {
                Section("Pinned") {
                    ForEach(pinned) { buffer in
                        OpenBufferRow(buffer: buffer)
                    }
                }
            }
            Section("Open") {
                ForEach(unpinned) { buffer in
                    OpenBufferRow(buffer: buffer)
                }
            }
            if !state.visibleRecents.isEmpty {
                Section("Recent") {
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
                TextField("Name", text: $draftName)
                    .textFieldStyle(.plain)
                    .focused($nameFieldFocused)
                    .onSubmit { state.rename(buffer, to: draftName) }
                    .onExitCommand { state.renamingID = nil }
                    .onChange(of: nameFieldFocused) { _, focused in
                        // Al perder el foco sin Enter ni Escape, confirma y desarma
                        // el campo (si no, se queda pegado y secuestra el siguiente clic).
                        if !focused && state.renamingID == buffer.id {
                            state.rename(buffer, to: draftName)
                        }
                    }
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
        .gesture(TapGesture(count: 2).onEnded {
            state.activeID = buffer.id
            state.renamingID = buffer.id
        })
        .simultaneousGesture(TapGesture(count: 1).onEnded {
            state.activeID = buffer.id
        })
        .overlay(MiddleClickCatcher { state.close(buffer) })
        .listRowBackground(isActive ? Color.accentColor.opacity(0.18) : Color.clear)
        .contextMenu {
            Button(buffer.isPinned ? "Unpin" : "Pin") { state.togglePin(buffer) }
            Button("Rename") { state.renamingID = buffer.id }
            Button("Save") { state.save(buffer) }
            if buffer.fileURL != nil || FileManager.default.fileExists(atPath: buffer.draftURL.path) {
                Button("Show in Finder") { state.showInFinder(buffer) }
            }
            Divider()
            Button("Close Tab") { state.close(buffer) }
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
                    Text("Unsaved note")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }
            }
            Spacer()
        }
        .contentShape(Rectangle())
        .onTapGesture { state.reopenRecent(entry) }
        .contextMenu {
            Button("Open") { state.reopenRecent(entry) }
            Button("Remove from Recents") { state.removeRecent(entry) }
        }
    }
}
