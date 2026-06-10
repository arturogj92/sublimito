import Foundation
import AppKit
import SwiftUI

struct RecentEntry: Codable, Identifiable, Equatable {
    enum Kind: String, Codable { case file, draft }
    var id: UUID
    var kind: Kind
    var path: String?    // solo para kind == .file
    var draftID: UUID?   // draft asociado (contenido sin guardar al cerrar)
    var name: String
    var date: Date
}

private struct BufferMeta: Codable {
    var id: UUID
    var path: String?
    var name: String
    var isPinned: Bool
    var isPreview: Bool
    var isLarge: Bool?
}

private struct SessionData: Codable {
    var buffers: [BufferMeta]
    var activeID: UUID?
}

@MainActor
final class AppState: ObservableObject {
    static let shared = AppState()

    @Published var buffers: [Buffer] = []
    @Published var activeID: UUID?
    @Published var recents: [RecentEntry] = []
    @Published var quickOpenShown = false
    @Published var shortcutsShown = false
    @Published var renamingID: UUID?

    struct PendingSelection {
        let bufferID: UUID
        let range: NSRange
    }
    /// Selección pendiente de aplicar en el editor (salto desde el buscador).
    @Published var pendingSelection: PendingSelection?

    @Published var sidebarVisible: Bool {
        didSet { UserDefaults.standard.set(sidebarVisible, forKey: "sidebarVisible") }
    }
    @Published var fontSize: CGFloat {
        didSet { UserDefaults.standard.set(Double(fontSize), forKey: "fontSize") }
    }
    @Published var wordWrap: Bool {
        didSet { UserDefaults.standard.set(wordWrap, forKey: "wordWrap") }
    }
    @Published var showLineNumbers: Bool {
        didSet { UserDefaults.standard.set(showLineNumbers, forKey: "showLineNumbers") }
    }
    @Published var minimapVisible: Bool {
        didSet { UserDefaults.standard.set(minimapVisible, forKey: "minimapVisible") }
    }
    @Published var findInFilesShown = false
    /// Incrementa para pedir foco en la barra de búsqueda del visor de ficheros grandes.
    @Published var largeFileFindRequest = 0
    @Published var folderURL: URL? {
        didSet { UserDefaults.standard.set(folderURL?.path, forKey: "folderPath") }
    }

    /// Por encima de este tamaño los ficheros se abren en el visor por streaming.
    static let largeFileThreshold: UInt64 = 10_000_000

    var activeBuffer: Buffer? { buffers.first { $0.id == activeID } }

    /// Pestañas con las fijadas primero, orden estable dentro de cada grupo.
    var orderedTabs: [Buffer] { buffers.filter(\.isPinned) + buffers.filter { !$0.isPinned } }

    /// Recientes que no están abiertos ahora mismo.
    var visibleRecents: [RecentEntry] {
        recents.filter { entry in
            !buffers.contains { buf in
                if let path = entry.path { return buf.fileURL?.path == path }
                if let dID = entry.draftID { return buf.id == dID }
                return false
            }
        }
    }

    // MARK: - Rutas

    static let supportDirectory: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("Sublimito", isDirectory: true)
        // Migración desde la época en que la app se llamaba Notable.
        let legacy = base.appendingPathComponent("Notable", isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path),
           FileManager.default.fileExists(atPath: legacy.path) {
            try? FileManager.default.moveItem(at: legacy, to: dir)
        }
        return dir
    }()
    static let draftsDirectory = supportDirectory.appendingPathComponent("Buffers", isDirectory: true)
    private static let sessionURL = supportDirectory.appendingPathComponent("session.json")
    private static let recentsURL = supportDirectory.appendingPathComponent("recents.json")

    private var autosaveWork: [UUID: DispatchWorkItem] = [:]
    private var persistWork: DispatchWorkItem?

    private init() {
        sidebarVisible = UserDefaults.standard.object(forKey: "sidebarVisible") as? Bool ?? true
        let storedSize = UserDefaults.standard.double(forKey: "fontSize")
        fontSize = storedSize >= 9 ? CGFloat(storedSize) : 13
        wordWrap = UserDefaults.standard.object(forKey: "wordWrap") as? Bool ?? true
        showLineNumbers = UserDefaults.standard.object(forKey: "showLineNumbers") as? Bool ?? true
        minimapVisible = UserDefaults.standard.object(forKey: "minimapVisible") as? Bool ?? true
        if let folderPath = UserDefaults.standard.string(forKey: "folderPath"),
           FileManager.default.fileExists(atPath: folderPath) {
            folderURL = URL(fileURLWithPath: folderPath)
        }
        try? FileManager.default.createDirectory(at: Self.draftsDirectory, withIntermediateDirectories: true)
        restore()
        if buffers.isEmpty { newBuffer() }
    }

    // MARK: - Crear y abrir

    func newBuffer() {
        let buffer = Buffer(name: nextUntitledName(), content: "")
        buffers.append(buffer)
        activeID = buffer.id
        persistSessionSoon()
    }

    private func nextUntitledName() -> String {
        let existing = Set(buffers.map(\.name))
        if !existing.contains("Untitled") { return "Untitled" }
        var n = 2
        while existing.contains("Untitled \(n)") { n += 1 }
        return "Untitled \(n)"
    }

    func openWithPanel() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        if panel.runModal() == .OK {
            for url in panel.urls { open(url: url) }
        }
    }

    func open(url rawURL: URL) {
        let url = rawURL.standardizedFileURL
        if let existing = buffers.first(where: { $0.fileURL?.path == url.path }) {
            activeID = existing.id
            return
        }
        let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? UInt64) ?? 0
        if size > Self.largeFileThreshold {
            let buffer = Buffer(fileURL: url, name: url.lastPathComponent, content: "")
            buffer.isLargeFile = true
            buffer.fileSize = size
            buffers.append(buffer)
            activeID = buffer.id
            addRecent(for: buffer)
            persistSessionSoon()
            return
        }
        guard let disk = Self.readText(at: url) else {
            Self.alert("Could Not Open", "Could not read \(url.lastPathComponent) as text.")
            return
        }
        // Si se cerró con cambios sin guardar, recupera el draft.
        var bufferID = UUID()
        var content = disk
        if let entry = recents.first(where: { $0.path == url.path }), let dID = entry.draftID,
           let draft = Self.readText(at: Self.draftsDirectory.appendingPathComponent(dID.uuidString + ".txt")) {
            bufferID = dID
            content = draft
        }
        let buffer = Buffer(id: bufferID, fileURL: url, name: url.lastPathComponent,
                            content: content, lastDiskContent: disk)
        buffers.append(buffer)
        activeID = buffer.id
        watch(buffer)
        addRecent(for: buffer)
        persistSessionSoon()
    }

    func reopenRecent(_ entry: RecentEntry) {
        if entry.kind == .file, let path = entry.path {
            open(url: URL(fileURLWithPath: path))
        } else if let dID = entry.draftID {
            if let existing = buffers.first(where: { $0.id == dID }) {
                activeID = existing.id
                return
            }
            let draftURL = Self.draftsDirectory.appendingPathComponent(dID.uuidString + ".txt")
            guard let draft = Self.readText(at: draftURL) else {
                Self.alert("Not Recoverable", "The content of \"\(entry.name)\" is no longer on disk.")
                recents.removeAll { $0.id == entry.id }
                persistRecentsSoon()
                return
            }
            let buffer = Buffer(id: dID, name: entry.name, content: draft)
            buffers.append(buffer)
            activeID = buffer.id
            persistSessionSoon()
        }
    }

    func removeRecent(_ entry: RecentEntry) {
        if entry.kind == .draft, let dID = entry.draftID {
            try? FileManager.default.removeItem(at: Self.draftsDirectory.appendingPathComponent(dID.uuidString + ".txt"))
        }
        recents.removeAll { $0.id == entry.id }
        persistRecentsSoon()
    }

    // MARK: - Edición y autosave

    func bufferEdited(_ buffer: Buffer) {
        if buffer.externalState == .reloaded { buffer.externalState = .none }
        autosaveWork[buffer.id]?.cancel()
        let work = DispatchWorkItem { [weak self, weak buffer] in
            guard let self, let buffer else { return }
            self.writeDraftNow(buffer)
        }
        autosaveWork[buffer.id] = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 2, execute: work)
        persistSessionSoon()
    }

    private func writeDraftNow(_ buffer: Buffer) {
        if buffer.needsDraft {
            try? buffer.content.write(to: buffer.draftURL, atomically: true, encoding: .utf8)
        } else {
            try? FileManager.default.removeItem(at: buffer.draftURL)
        }
    }

    // MARK: - Guardar

    func saveActive() { if let b = activeBuffer { save(b) } }
    func saveActiveAs() { if let b = activeBuffer { saveAs(b) } }

    func save(_ buffer: Buffer) {
        guard !buffer.isLargeFile else { return }
        MonacoController.shared.flushPendingEdits()
        guard let url = buffer.fileURL else {
            saveAs(buffer)
            return
        }
        performSave(buffer, to: url)
    }

    func saveAs(_ buffer: Buffer) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = buffer.name.contains(".") ? buffer.name : buffer.name + ".md"
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let wasTemp = buffer.fileURL == nil
        buffer.fileURL = url.standardizedFileURL
        buffer.name = url.lastPathComponent
        performSave(buffer, to: url.standardizedFileURL)
        if wasTemp {
            buffer.watcher?.stop()
            buffer.watcher = nil
            watch(buffer)
            // El temporal deja de existir: su sitio físico es ya el fichero elegido.
            recents.removeAll { $0.draftID == buffer.id && $0.kind == .draft }
        }
        objectWillChange.send()
        persistSessionSoon()
    }

    private func performSave(_ buffer: Buffer, to url: URL) {
        buffer.watcher?.suppress(for: 1.5)
        do {
            try buffer.content.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            Self.alert("Could Not Save", error.localizedDescription)
            return
        }
        buffer.lastDiskContent = buffer.content
        buffer.pendingDiskContent = nil
        buffer.externalState = .none
        autosaveWork[buffer.id]?.cancel()
        try? FileManager.default.removeItem(at: buffer.draftURL)
        // La escritura atómica reemplaza el inode: hay que rearmar el watcher.
        buffer.watcher?.restart()
        buffer.watcher?.suppress(for: 1.5)
        addRecent(for: buffer)
        objectWillChange.send()
    }

    // MARK: - Cerrar

    func closeActive() { if let b = activeBuffer { close(b) } }

    func close(_ buffer: Buffer) {
        MonacoController.shared.closeBuffer(buffer.id)
        buffer.watcher?.stop()
        buffer.watcher = nil
        autosaveWork[buffer.id]?.cancel()
        writeDraftNow(buffer)
        addRecent(for: buffer, closing: true)

        let tabs = orderedTabs
        let closedIndex = tabs.firstIndex { $0.id == buffer.id }
        buffers.removeAll { $0.id == buffer.id }
        if activeID == buffer.id {
            let remaining = orderedTabs
            if remaining.isEmpty {
                newBuffer()
            } else {
                let idx = min(closedIndex ?? 0, remaining.count - 1)
                activeID = remaining[idx].id
            }
        }
        if buffers.isEmpty { newBuffer() }
        persistSessionSoon()
        persistRecentsSoon()
    }

    // MARK: - Fijar y renombrar

    func togglePin(_ buffer: Buffer) {
        buffer.isPinned.toggle()
        objectWillChange.send()
        persistSessionSoon()
    }

    func rename(_ buffer: Buffer, to rawName: String) {
        let newName = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        renamingID = nil
        guard !newName.isEmpty, newName != buffer.name else { return }
        if let url = buffer.fileURL {
            let dest = url.deletingLastPathComponent().appendingPathComponent(newName)
            buffer.watcher?.suppress(for: 1.5)
            do {
                try FileManager.default.moveItem(at: url, to: dest)
            } catch {
                Self.alert("Could Not Rename", error.localizedDescription)
                return
            }
            buffer.fileURL = dest
            buffer.name = newName
            buffer.watcher?.stop()
            buffer.watcher = nil
            watch(buffer)
            recents.removeAll { $0.path == url.path }
            addRecent(for: buffer)
        } else {
            buffer.name = newName
        }
        objectWillChange.send()
        persistSessionSoon()
    }

    // MARK: - Cambios externos

    private func watch(_ buffer: Buffer) {
        guard let url = buffer.fileURL, !buffer.isLargeFile else { return }
        buffer.watcher = FileWatcher(url: url) { [weak self, weak buffer] in
            guard let self, let buffer else { return }
            self.handleExternalEvent(buffer)
        }
    }

    func handleExternalEvent(_ buffer: Buffer) {
        guard let url = buffer.fileURL else { return }
        if !FileManager.default.fileExists(atPath: url.path) {
            // Borrado o renombrado fuera: el buffer pasa a temporal respaldado, no se pierde nada.
            buffer.watcher?.stop()
            buffer.watcher = nil
            recents.removeAll { $0.path == url.path }
            buffer.fileURL = nil
            buffer.lastDiskContent = nil
            buffer.externalState = .fileDisappeared
            writeDraftNow(buffer)
            objectWillChange.send()
            persistSessionSoon()
            persistRecentsSoon()
            return
        }
        guard let disk = Self.readText(at: url), disk != buffer.lastDiskContent else { return }
        if !buffer.isDirty {
            buffer.setContentProgrammatically(disk)
            buffer.lastDiskContent = disk
            buffer.externalState = .reloaded
            let id = buffer.id
            DispatchQueue.main.asyncAfter(deadline: .now() + 4) { [weak self] in
                guard let self, let b = self.buffers.first(where: { $0.id == id }),
                      b.externalState == .reloaded else { return }
                b.externalState = .none
            }
        } else {
            buffer.pendingDiskContent = disk
            buffer.externalState = .conflict
        }
    }

    func resolveConflictReloadFromDisk(_ buffer: Buffer) {
        guard let url = buffer.fileURL, let disk = Self.readText(at: url) ?? buffer.pendingDiskContent.map({ $0 }) else { return }
        buffer.setContentProgrammatically(disk)
        buffer.lastDiskContent = disk
        buffer.pendingDiskContent = nil
        buffer.externalState = .none
        autosaveWork[buffer.id]?.cancel()
        try? FileManager.default.removeItem(at: buffer.draftURL)
    }

    func resolveConflictKeepMine(_ buffer: Buffer) {
        if let disk = buffer.pendingDiskContent {
            buffer.lastDiskContent = disk // sigue dirty respecto al disco nuevo
        }
        buffer.pendingDiskContent = nil
        buffer.externalState = .none
        writeDraftNow(buffer)
    }

    // MARK: - Navegación

    func selectRelative(_ offset: Int) {
        let tabs = orderedTabs
        guard tabs.count > 1, let current = tabs.firstIndex(where: { $0.id == activeID }) else { return }
        let next = (current + offset + tabs.count) % tabs.count
        activeID = tabs[next].id
    }

    func togglePreview() {
        guard let buffer = activeBuffer else { return }
        buffer.isPreview.toggle()
        persistSessionSoon()
    }

    func showInFinder(_ buffer: Buffer) {
        let url = buffer.fileURL ?? (FileManager.default.fileExists(atPath: buffer.draftURL.path) ? buffer.draftURL : nil)
        if let url { NSWorkspace.shared.activateFileViewerSelecting([url]) }
    }

    // MARK: - Carpeta de proyecto

    func openFolderWithPanel() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            folderURL = url.standardizedFileURL
        }
    }

    func closeFolder() {
        folderURL = nil
    }

    // MARK: - Recientes

    private func addRecent(for buffer: Buffer, closing: Bool = false) {
        var entry: RecentEntry
        if let url = buffer.fileURL {
            entry = RecentEntry(id: UUID(), kind: .file, path: url.path,
                                draftID: (closing && buffer.isDirty) ? buffer.id : nil,
                                name: buffer.name, date: Date())
            recents.removeAll { $0.path == url.path }
        } else {
            entry = RecentEntry(id: UUID(), kind: .draft, path: nil, draftID: buffer.id,
                                name: buffer.name, date: Date())
            recents.removeAll { $0.draftID == buffer.id }
        }
        recents.insert(entry, at: 0)
        if recents.count > 30 { recents.removeLast(recents.count - 30) }
        persistRecentsSoon()
    }

    // MARK: - Persistencia

    func persistSessionSoon() {
        persistWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.persistSessionNow() }
        persistWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1, execute: work)
    }

    private func persistSessionNow() {
        let metas = buffers.map {
            BufferMeta(id: $0.id, path: $0.fileURL?.path, name: $0.name,
                       isPinned: $0.isPinned, isPreview: $0.isPreview, isLarge: $0.isLargeFile)
        }
        let data = SessionData(buffers: metas, activeID: activeID)
        if let encoded = try? JSONEncoder().encode(data) {
            try? encoded.write(to: Self.sessionURL, options: .atomic)
        }
    }

    func persistRecentsSoon() { persistRecentsNow() }

    private func persistRecentsNow() {
        if let encoded = try? JSONEncoder().encode(recents) {
            try? encoded.write(to: Self.recentsURL, options: .atomic)
        }
    }

    private func restore() {
        if let data = try? Data(contentsOf: Self.recentsURL),
           let decoded = try? JSONDecoder().decode([RecentEntry].self, from: data) {
            recents = decoded
        }
        guard let data = try? Data(contentsOf: Self.sessionURL),
              let session = try? JSONDecoder().decode(SessionData.self, from: data) else { return }
        for meta in session.buffers {
            if meta.isLarge == true, let path = meta.path {
                let url = URL(fileURLWithPath: path)
                guard let size = try? FileManager.default.attributesOfItem(atPath: path)[.size] as? UInt64 else { continue }
                let buffer = Buffer(id: meta.id, fileURL: url, name: meta.name, content: "",
                                    isPinned: meta.isPinned)
                buffer.isLargeFile = true
                buffer.fileSize = size
                buffers.append(buffer)
                continue
            }
            let draftURL = Self.draftsDirectory.appendingPathComponent(meta.id.uuidString + ".txt")
            let draft = Self.readText(at: draftURL)
            var fileURL: URL?
            var disk: String?
            if let path = meta.path {
                let url = URL(fileURLWithPath: path)
                disk = Self.readText(at: url)
                if disk != nil { fileURL = url }
            }
            let content = draft ?? disk ?? ""
            if meta.path != nil && disk == nil && draft == nil { continue } // fichero desaparecido sin respaldo
            let buffer = Buffer(id: meta.id, fileURL: fileURL, name: meta.name, content: content,
                                lastDiskContent: disk, isPinned: meta.isPinned, isPreview: meta.isPreview)
            buffers.append(buffer)
            watch(buffer)
        }
        if let active = session.activeID, buffers.contains(where: { $0.id == active }) {
            activeID = active
        } else {
            activeID = orderedTabs.first?.id
        }
    }

    /// Volcado síncrono de todo antes de salir. Hot exit.
    func flushAllNow() {
        for buffer in buffers {
            autosaveWork[buffer.id]?.cancel()
            writeDraftNow(buffer)
        }
        persistWork?.cancel()
        persistSessionNow()
        persistRecentsNow()
    }

    // MARK: - Utilidades

    static func readText(at url: URL) -> String? {
        if let s = try? String(contentsOf: url, encoding: .utf8) { return s }
        if let s = try? String(contentsOf: url, encoding: .isoLatin1) { return s }
        return nil
    }

    static func alert(_ title: String, _ message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.runModal()
    }
}
