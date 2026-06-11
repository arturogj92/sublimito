import SwiftUI
import UniformTypeIdentifiers

struct TabBarView: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 1) {
                    ForEach(state.orderedTabs) { buffer in
                        TabItemView(buffer: buffer)
                            .id(buffer.id)
                            .onDrag {
                                state.draggingTabID = buffer.id
                                return NSItemProvider(object: buffer.id.uuidString as NSString)
                            }
                            .onDrop(of: [.plainText], delegate: TabReorderDropDelegate(targetID: buffer.id, state: state))
                    }
                    Button(action: { state.newBuffer() }) {
                        Image(systemName: "plus")
                            .font(.system(size: 11, weight: .medium))
                            .frame(width: 28, height: 30)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .help("New note (Cmd+N)")
                }
            }
            .onChange(of: state.activeID) { _, newValue in
                if let newValue { withAnimation { proxy.scrollTo(newValue) } }
            }
        }
        .frame(height: 30)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

/// Reordena en vivo: al entrar el arrastre sobre otra pestaña, mueve la arrastrada
/// a su posición. El drop solo confirma (el orden ya cambió durante el arrastre).
private struct TabReorderDropDelegate: DropDelegate {
    let targetID: UUID
    let state: AppState

    func dropEntered(info: DropInfo) {
        guard let dragged = state.draggingTabID else { return }
        state.moveTab(id: dragged, to: targetID)
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: state.draggingTabID == nil ? .forbidden : .move)
    }

    func validateDrop(info: DropInfo) -> Bool {
        state.draggingTabID != nil
    }

    func performDrop(info: DropInfo) -> Bool {
        state.draggingTabID = nil
        return true
    }
}

private struct TabItemView: View {
    @ObservedObject var buffer: Buffer
    @EnvironmentObject var state: AppState
    @State private var hovering = false

    var isActive: Bool { state.activeID == buffer.id }

    var body: some View {
        HStack(spacing: 5) {
            if buffer.isPinned {
                Image(systemName: "pin.fill")
                    .font(.system(size: 8))
                    .foregroundStyle(.orange)
            }
            Text(buffer.name)
                .font(.system(size: 12))
                .lineLimit(1)
            if buffer.isDirty {
                Circle().fill(Color.secondary).frame(width: 5, height: 5)
            }
            Button(action: { state.close(buffer) }) {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .opacity(hovering ? 1 : 0)
            .help("Close tab (Cmd+W)")
        }
        .padding(.horizontal, 10)
        .frame(height: 30)
        .background(isActive ? Color(nsColor: .textBackgroundColor) : Color.clear)
        .overlay(alignment: .bottom) {
            if isActive { Rectangle().fill(Color.accentColor).frame(height: 2) }
        }
        .contentShape(Rectangle())
        .gesture(TapGesture(count: 2).onEnded {
            state.activeID = buffer.id
            state.sidebarVisible = true // el campo de renombrar vive en la sidebar
            state.renamingID = buffer.id
        })
        .simultaneousGesture(TapGesture(count: 1).onEnded {
            state.activeID = buffer.id
        })
        .overlay(MiddleClickCatcher { state.close(buffer) })
        .pointingHandCursor()
        .onHover { hovering = $0 }
        .contextMenu {
            Button(buffer.isPinned ? "Unpin" : "Pin") { state.togglePin(buffer) }
            Button("Rename") { state.renamingID = buffer.id }
            Button("Save") { state.save(buffer) }
            Button("Show in Finder") { state.showInFinder(buffer) }
            Divider()
            Button("Close Tab") { state.close(buffer) }
        }
    }
}
