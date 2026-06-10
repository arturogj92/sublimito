import Foundation
import AppKit

enum ExternalState: Equatable {
    case none
    case conflict        // el fichero cambió en disco y hay cambios locales sin guardar
    case fileDisappeared // el fichero se borró o renombró fuera; el buffer pasó a temporal
    case reloaded        // recargado automáticamente desde disco (aviso transitorio)
}

@MainActor
final class Buffer: ObservableObject, Identifiable {
    let id: UUID

    @Published var fileURL: URL?
    @Published var name: String
    @Published var isPinned: Bool
    @Published var isPreview: Bool = false
    @Published var externalState: ExternalState = .none

    /// Ficheros enormes: se abren en el visor por streaming, sin cargar el contenido.
    var isLargeFile = false
    var fileSize: UInt64 = 0

    /// Contenido del fichero en disco la última vez que se leyó o guardó. nil para buffers temporales.
    var lastDiskContent: String?
    /// Contenido pendiente de disco cuando hay conflicto.
    var pendingDiskContent: String?

    let undoManager = UndoManager()
    var watcher: FileWatcher?

    /// Evita que cambios programáticos (recargas, restore) disparen autosave o bucles.
    var suppressChangeNotifications = false

    @Published var content: String {
        didSet {
            guard !suppressChangeNotifications else { return }
            AppState.shared.bufferEdited(self)
        }
    }

    var isDirty: Bool {
        guard let disk = lastDiskContent else { return false }
        return content != disk
    }

    /// Un buffer necesita draft si es temporal o si tiene cambios sin guardar sobre su fichero.
    var needsDraft: Bool {
        !isLargeFile && (fileURL == nil || isDirty)
    }

    var draftURL: URL {
        AppState.draftsDirectory.appendingPathComponent(id.uuidString + ".txt")
    }

    var isMarkdown: Bool {
        guard let url = fileURL else { return true } // a los temporales se les permite preview siempre
        let ext = url.pathExtension.lowercased()
        return ["md", "markdown", "mdown", "mkd", "txt", ""].contains(ext)
    }

    init(id: UUID = UUID(), fileURL: URL? = nil, name: String, content: String,
         lastDiskContent: String? = nil, isPinned: Bool = false, isPreview: Bool = false) {
        self.id = id
        self.fileURL = fileURL
        self.name = name
        self.content = content
        self.lastDiskContent = lastDiskContent
        self.isPinned = isPinned
        self.isPreview = isPreview
    }

    func setContentProgrammatically(_ newContent: String) {
        suppressChangeNotifications = true
        content = newContent
        suppressChangeNotifications = false
    }
}
