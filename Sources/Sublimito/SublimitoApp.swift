import SwiftUI
import AppKit
import Sparkle

@main
struct SublimitoApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var state = AppState.shared
    private let updaterController = SPUStandardUpdaterController(
        startingUpdater: true,
        updaterDelegate: nil,
        userDriverDelegate: nil
    )

    var body: some Scene {
        Window("Sublimito", id: "main") {
            ContentView()
                .environmentObject(state)
        }
        // Sin esto, SwiftUI re-presenta la ventana (close + reopen visible) al recibir
        // el evento de abrir documento; los ficheros ya los gestiona el AppDelegate.
        .handlesExternalEvents(matching: [])
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(after: .appInfo) {
                CheckForUpdatesView(updater: updaterController.updater)
            }
            SublimitoCommands(state: state)
        }
    }
}

struct CheckForUpdatesView: View {
    @ObservedObject private var viewModel: CheckForUpdatesViewModel
    private let updater: SPUUpdater

    init(updater: SPUUpdater) {
        self.updater = updater
        self.viewModel = CheckForUpdatesViewModel(updater: updater)
    }

    var body: some View {
        Button("Check for Updates…", action: updater.checkForUpdates)
            .disabled(!viewModel.canCheckForUpdates)
    }
}

final class CheckForUpdatesViewModel: ObservableObject {
    @Published var canCheckForUpdates = false

    init(updater: SPUUpdater) {
        updater.publisher(for: \.canCheckForUpdates)
            .assign(to: &$canCheckForUpdates)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSWindow.allowsAutomaticWindowTabbing = false
    }

    // Ficheros abiertos desde Finder, dock o "Abrir con": siempre a la ventana única.
    // LaunchServices ya activa la app en aperturas iniciadas por el usuario; cualquier
    // activate() extra aquí interfiere con ese traspaso y rebota la ventana.
    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            AppState.shared.open(url: url)
        }
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
            Button("New Note") { state.newBuffer() }
                .keyboardShortcut("n", modifiers: .command)
            Button("Open…") { state.openWithPanel() }
                .keyboardShortcut("o", modifiers: .command)
            Button("Open Folder…") { state.openFolderWithPanel() }
                .keyboardShortcut("o", modifiers: [.command, .shift])
            if state.folderURL != nil {
                Button("Close Folder") { state.closeFolder() }
            }
        }
        CommandGroup(replacing: .saveItem) {
            Button("Save") { state.saveActive() }
                .keyboardShortcut("s", modifiers: .command)
            Button("Save As…") { state.saveActiveAs() }
                .keyboardShortcut("s", modifiers: [.command, .shift])
            Divider()
            Button("Close Tab") { state.closeActive() }
                .keyboardShortcut("w", modifiers: .command)
            Button("Reopen Closed Tab") { state.reopenLastClosed() }
                .keyboardShortcut("t", modifiers: [.command, .shift])
        }
        CommandGroup(replacing: .printItem) {
            Button("Go to Tab or Recent…") { state.quickOpenShown = true }
                .keyboardShortcut("p", modifiers: .command)
        }
        CommandGroup(after: .pasteboard) {
            Divider()
            Menu("Find") {
                Button("Find…") { FindActions.send(.find) }
                    .keyboardShortcut("f", modifiers: .command)
                Button("Find & Replace…") { FindActions.send(.findReplace) }
                    .keyboardShortcut("f", modifiers: [.command, .option])
                Divider()
                Button("Find Next") { FindActions.send(.findNext) }
                    .keyboardShortcut("g", modifiers: .command)
                Button("Find Previous") { FindActions.send(.findPrev) }
                    .keyboardShortcut("g", modifiers: [.command, .shift])
                Divider()
                Divider()
                Button("Find in Files…") { state.findInFilesShown = true }
                    .keyboardShortcut("f", modifiers: [.command, .shift])
            }
        }
        CommandMenu("View") {
            Button(state.activeBuffer?.isPreview == true ? "Edit Text" : "Markdown Preview") {
                state.togglePreview()
            }
            .keyboardShortcut("p", modifiers: [.command, .shift])
            Button(state.sidebarVisible ? "Hide Sidebar" : "Show Sidebar") {
                state.sidebarVisible.toggle()
            }
            .keyboardShortcut("b", modifiers: .command)
            Divider()
            Toggle("Word Wrap", isOn: Binding(
                get: { state.wordWrap },
                set: { state.wordWrap = $0 }
            ))
            Toggle("Line Numbers", isOn: Binding(
                get: { state.showLineNumbers },
                set: { state.showLineNumbers = $0 }
            ))
            Toggle("Minimap", isOn: Binding(
                get: { state.minimapVisible },
                set: { state.minimapVisible = $0 }
            ))
            Divider()
            Button("Increase Font Size") { state.fontSize = min(32, state.fontSize + 1) }
                .keyboardShortcut("+", modifiers: .command)
            Button("Decrease Font Size") { state.fontSize = max(9, state.fontSize - 1) }
                .keyboardShortcut("-", modifiers: .command)
            Button("Default Font Size") { state.fontSize = 13 }
                .keyboardShortcut("0", modifiers: .command)
            Divider()
            Button("Next Tab") { state.selectRelative(1) }
                .keyboardShortcut("]", modifiers: [.command, .shift])
            Button("Previous Tab") { state.selectRelative(-1) }
                .keyboardShortcut("[", modifiers: [.command, .shift])
        }
        CommandGroup(replacing: .help) {
            Button("Keyboard Shortcuts") { state.shortcutsShown = true }
                .keyboardShortcut("?", modifiers: .command)
        }
    }
}
