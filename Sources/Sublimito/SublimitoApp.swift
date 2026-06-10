import SwiftUI
import AppKit

@main
struct SublimitoApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var state = AppState.shared

    var body: some Scene {
        Window("Sublimito", id: "main") {
            ContentView()
                .environmentObject(state)
        }
        .windowToolbarStyle(.unified)
        .commands {
            SublimitoCommands(state: state)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSWindow.allowsAutomaticWindowTabbing = false
    }

    // Ficheros abiertos desde Finder, dock o "Abrir con": siempre a la ventana única.
    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            AppState.shared.open(url: url)
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Hot exit: volcar todos los drafts y la sesión antes de morir.
        AppState.shared.flushAllNow()
    }
}

struct SublimitoCommands: Commands {
    @ObservedObject var state: AppState

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("Nueva nota") { state.newBuffer() }
                .keyboardShortcut("n", modifiers: .command)
            Button("Abrir…") { state.openWithPanel() }
                .keyboardShortcut("o", modifiers: .command)
        }
        CommandGroup(replacing: .saveItem) {
            Button("Guardar") { state.saveActive() }
                .keyboardShortcut("s", modifiers: .command)
            Button("Guardar como…") { state.saveActiveAs() }
                .keyboardShortcut("s", modifiers: [.command, .shift])
            Divider()
            Button("Cerrar pestaña") { state.closeActive() }
                .keyboardShortcut("w", modifiers: .command)
        }
        CommandGroup(replacing: .printItem) {
            Button("Ir a pestaña o reciente…") { state.quickOpenShown = true }
                .keyboardShortcut("p", modifiers: .command)
        }
        CommandGroup(after: .pasteboard) {
            Divider()
            Menu("Buscar") {
                Button("Buscar…") { FindActions.send(.showFindInterface) }
                    .keyboardShortcut("f", modifiers: .command)
                Button("Buscar y reemplazar…") { FindActions.send(.showReplaceInterface) }
                    .keyboardShortcut("f", modifiers: [.command, .option])
                Divider()
                Button("Siguiente coincidencia") { FindActions.send(.nextMatch) }
                    .keyboardShortcut("g", modifiers: .command)
                Button("Coincidencia anterior") { FindActions.send(.previousMatch) }
                    .keyboardShortcut("g", modifiers: [.command, .shift])
                Divider()
                Button("Usar selección para buscar") { FindActions.send(.setSearchString) }
                    .keyboardShortcut("e", modifiers: .command)
            }
        }
        CommandMenu("Ver") {
            Button(state.activeBuffer?.isPreview == true ? "Editar texto" : "Vista Markdown") {
                state.togglePreview()
            }
            .keyboardShortcut("p", modifiers: [.command, .shift])
            Button(state.sidebarVisible ? "Ocultar barra lateral" : "Mostrar barra lateral") {
                state.sidebarVisible.toggle()
            }
            .keyboardShortcut("b", modifiers: .command)
            Divider()
            Toggle("Ajuste de línea", isOn: Binding(
                get: { state.wordWrap },
                set: { state.wordWrap = $0 }
            ))
            Toggle("Números de línea", isOn: Binding(
                get: { state.showLineNumbers },
                set: { state.showLineNumbers = $0 }
            ))
            Divider()
            Button("Aumentar fuente") { state.fontSize = min(32, state.fontSize + 1) }
                .keyboardShortcut("+", modifiers: .command)
            Button("Reducir fuente") { state.fontSize = max(9, state.fontSize - 1) }
                .keyboardShortcut("-", modifiers: .command)
            Button("Tamaño por defecto") { state.fontSize = 13 }
                .keyboardShortcut("0", modifiers: .command)
            Divider()
            Button("Pestaña siguiente") { state.selectRelative(1) }
                .keyboardShortcut("]", modifiers: [.command, .shift])
            Button("Pestaña anterior") { state.selectRelative(-1) }
                .keyboardShortcut("[", modifiers: [.command, .shift])
        }
        CommandGroup(replacing: .help) {}
    }
}
