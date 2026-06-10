import AppKit

/// Acciones de búsqueda del menú. En el editor Monaco usan su find widget
/// (con regex, case y whole word). En el visor de ficheros grandes enfocan
/// la barra de búsqueda de fichero completo.
enum FindActions {
    @MainActor
    static func send(_ command: MonacoController.FindCommand) {
        guard let buffer = AppState.shared.activeBuffer else { return }
        if buffer.isLargeFile {
            AppState.shared.largeFileFindRequest += 1
            return
        }
        MonacoController.shared.runFind(command)
    }
}
