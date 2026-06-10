import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @EnvironmentObject var state: AppState
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 180, ideal: 240, max: 400)
        } detail: {
            mainArea
        }
        .overlay {
            if state.quickOpenShown { QuickOpenView() }
        }
        .overlay {
            if state.findInFilesShown { FindInFilesView() }
        }
        .sheet(isPresented: $state.shortcutsShown) {
            ShortcutsView()
                .environmentObject(state)
        }
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            for provider in providers {
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    guard let url, url.isFileURL else { return }
                    Task { @MainActor in AppState.shared.open(url: url) }
                }
            }
            return true
        }
        .navigationTitle(state.activeBuffer?.name ?? "Sublimito")
        .frame(minWidth: 700, minHeight: 420)
        .onAppear { columnVisibility = state.sidebarVisible ? .all : .detailOnly }
        .onChange(of: state.sidebarVisible) { _, visible in
            columnVisibility = visible ? .all : .detailOnly
        }
        .onChange(of: columnVisibility) { _, visibility in
            let visible = visibility != .detailOnly
            if state.sidebarVisible != visible { state.sidebarVisible = visible }
        }
    }

    private var mainArea: some View {
        VStack(spacing: 0) {
            TabBarView()
            Divider()
            if let buffer = state.activeBuffer {
                BufferContainerView(buffer: buffer)
            } else {
                Spacer()
                Text("Cmd+N to create a note")
                    .foregroundStyle(.secondary)
                Spacer()
            }
        }
    }
}

private struct BufferContainerView: View {
    @ObservedObject var buffer: Buffer
    @EnvironmentObject var state: AppState

    var body: some View {
        VStack(spacing: 0) {
            banner
            if buffer.isLargeFile {
                LargeFileView(buffer: buffer)
                    .id(buffer.id)
            } else if buffer.isPreview {
                MarkdownPreviewView(buffer: buffer)
                    .overlay(alignment: .topTrailing) { copyRawButton }
            } else {
                MonacoEditorView(buffer: buffer)
            }
            Divider()
            StatusBarView(buffer: buffer)
        }
    }

    @ViewBuilder
    private var banner: some View {
        switch buffer.externalState {
        case .conflict:
            BannerView(color: .orange,
                       icon: "exclamationmark.triangle.fill",
                       text: "The file changed on disk and you have unsaved changes.") {
                Button("Reload from Disk") { state.resolveConflictReloadFromDisk(buffer) }
                Button("Keep Mine") { state.resolveConflictKeepMine(buffer) }
            }
        case .fileDisappeared:
            BannerView(color: .red,
                       icon: "trash.slash.fill",
                       text: "The file disappeared from disk. This tab is still backed up as a temporary note.") {
                Button("Save As…") { state.saveAs(buffer) }
                Button("Got It") { buffer.externalState = .none }
            }
        case .reloaded:
            BannerView(color: .blue,
                       icon: "arrow.triangle.2.circlepath",
                       text: "Reloaded automatically: the file changed on disk.") {
                EmptyView()
            }
        case .none:
            EmptyView()
        }
    }

    private var copyRawButton: some View {
        Button(action: copyRaw) {
            Label("Copy Raw", systemImage: "doc.on.doc")
                .font(.system(size: 11, weight: .medium))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(.regularMaterial, in: Capsule())
                .overlay(Capsule().strokeBorder(.separator, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .padding(12)
        .help("Copy the raw Markdown source to the clipboard")
    }

    private func copyRaw() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(buffer.content, forType: .string)
    }
}

private struct BannerView<Actions: View>: View {
    let color: Color
    let icon: String
    let text: String
    @ViewBuilder let actions: Actions

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon).foregroundStyle(color)
            Text(text).font(.system(size: 12))
            Spacer()
            actions
                .buttonStyle(.bordered)
                .controlSize(.small)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(color.opacity(0.12))
    }
}

private struct StatusBarView: View {
    @ObservedObject var buffer: Buffer
    @EnvironmentObject var state: AppState

    private var words: Int {
        buffer.content.split { $0.isWhitespace || $0.isNewline }.count
    }
    private var lines: Int {
        buffer.content.isEmpty ? 1 : buffer.content.reduce(into: 1) { if $1 == "\n" { $0 += 1 } }
    }

    var body: some View {
        HStack(spacing: 14) {
            if buffer.isLargeFile {
                if let url = buffer.fileURL {
                    Button(action: { state.showInFinder(buffer) }) {
                        Text(url.path).lineLimit(1).truncationMode(.head)
                    }
                    .buttonStyle(.plain)
                    .help("Show in Finder")
                }
                Spacer()
                Text(LargeFileModel.format(buffer.fileSize))
            } else if let url = buffer.fileURL {
                Button(action: { state.showInFinder(buffer) }) {
                    Text(url.path)
                        .lineLimit(1)
                        .truncationMode(.head)
                }
                .buttonStyle(.plain)
                .help("Show in Finder")
            } else {
                Label("Temporary note, backed up automatically", systemImage: "internaldrive")
            }
            if !buffer.isLargeFile {
                Spacer()
                Text("\(lines) lines")
                Text("\(words) words")
                Text("\(buffer.content.count) characters")
                Button(action: { state.togglePreview() }) {
                    Label(buffer.isPreview ? "Edit" : "Markdown",
                          systemImage: buffer.isPreview ? "pencil" : "eye")
                        .font(.system(size: 11))
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.accentColor)
                .help("Toggle Markdown preview (Cmd+Shift+P)")
            }
        }
        .font(.system(size: 11))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .frame(height: 26)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}
