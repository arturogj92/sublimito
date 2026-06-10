import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        HStack(spacing: 0) {
            if state.sidebarVisible {
                SidebarView()
                    .frame(width: 240)
                Divider()
            }
            mainArea
        }
        .overlay {
            if state.quickOpenShown { QuickOpenView() }
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
        .navigationSubtitle(state.activeBuffer?.fileURL?.deletingLastPathComponent().path ?? "")
        .frame(minWidth: 700, minHeight: 420)
    }

    private var mainArea: some View {
        VStack(spacing: 0) {
            TabBarView()
            Divider()
            if let buffer = state.activeBuffer {
                BufferContainerView(buffer: buffer)
                    .id(buffer.id)
            } else {
                Spacer()
                Text("Cmd+N para crear una nota")
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
            if buffer.isPreview {
                MarkdownPreviewView(buffer: buffer)
                    .overlay(alignment: .topTrailing) { copyRawButton }
            } else {
                EditorTextView(buffer: buffer, fontSize: state.fontSize,
                               wordWrap: state.wordWrap, showLineNumbers: state.showLineNumbers)
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
                       text: "El fichero ha cambiado en disco y tienes cambios sin guardar.") {
                Button("Recargar del disco") { state.resolveConflictReloadFromDisk(buffer) }
                Button("Mantener lo mío") { state.resolveConflictKeepMine(buffer) }
            }
        case .fileDisappeared:
            BannerView(color: .red,
                       icon: "trash.slash.fill",
                       text: "El fichero ha desaparecido del disco. La pestaña sigue respaldada como nota temporal.") {
                Button("Guardar como…") { state.saveAs(buffer) }
                Button("Entendido") { buffer.externalState = .none }
            }
        case .reloaded:
            BannerView(color: .blue,
                       icon: "arrow.triangle.2.circlepath",
                       text: "Recargado automáticamente: el fichero cambió en disco.") {
                EmptyView()
            }
        case .none:
            EmptyView()
        }
    }

    private var copyRawButton: some View {
        Button(action: copyRaw) {
            Label("Copiar raw", systemImage: "doc.on.doc")
                .font(.system(size: 11, weight: .medium))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(.regularMaterial, in: Capsule())
                .overlay(Capsule().strokeBorder(.separator, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .padding(12)
        .help("Copiar el Markdown sin formato al portapapeles")
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
            if let url = buffer.fileURL {
                Button(action: { state.showInFinder(buffer) }) {
                    Text(url.path)
                        .lineLimit(1)
                        .truncationMode(.head)
                }
                .buttonStyle(.plain)
                .help("Mostrar en Finder")
            } else {
                Label("Nota temporal, respaldada automáticamente", systemImage: "internaldrive")
            }
            Spacer()
            Text("\(lines) líneas")
            Text("\(words) palabras")
            Text("\(buffer.content.count) caracteres")
            Button(action: { state.togglePreview() }) {
                Label(buffer.isPreview ? "Editar" : "Markdown",
                      systemImage: buffer.isPreview ? "pencil" : "eye")
                    .font(.system(size: 11))
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.accentColor)
            .help("Alternar vista Markdown (Cmd+Shift+P)")
        }
        .font(.system(size: 11))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .frame(height: 26)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}
