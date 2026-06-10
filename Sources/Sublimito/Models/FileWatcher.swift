import Foundation

/// Vigila un fichero en disco con DispatchSource. Detecta escrituras, borrados y renames
/// (git y muchos editores reemplazan ficheros via rename, asi que hay que rearmar el fd).
final class FileWatcher {
    private let url: URL
    private let onEvent: @MainActor () -> Void
    private var source: DispatchSourceFileSystemObject?
    private var suppressUntil = Date.distantPast
    private var stopped = false

    init(url: URL, onEvent: @escaping @MainActor () -> Void) {
        self.url = url
        self.onEvent = onEvent
        start()
    }

    /// Ignora eventos durante un intervalo (para guardados hechos por la propia app).
    func suppress(for seconds: TimeInterval = 1.0) {
        suppressUntil = Date().addingTimeInterval(seconds)
    }

    func stop() {
        stopped = true
        source?.cancel()
        source = nil
    }

    /// Rearma el watcher (necesario tras guardados atómicos propios, que invalidan el fd).
    func restart() {
        source?.cancel()
        source = nil
        start()
    }

    private func start() {
        guard !stopped else { return }
        let fd = open(url.path, O_EVTONLY)
        guard fd >= 0 else {
            // El fichero puede no existir todavía (rename en curso). Reintenta una vez.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                guard let self, !self.stopped, self.source == nil else { return }
                let fd2 = open(self.url.path, O_EVTONLY)
                if fd2 >= 0 { self.attach(fd: fd2) } else { self.notify() }
            }
            return
        }
        attach(fd: fd)
    }

    private func attach(fd: Int32) {
        let src = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .extend, .delete, .rename, .attrib],
            queue: .main
        )
        src.setEventHandler { [weak self] in
            guard let self else { return }
            let flags = src.data
            let needsRearm = flags.contains(.delete) || flags.contains(.rename)
            if needsRearm {
                // El fd ya no apunta al path: rearmar sobre el path tras un respiro.
                self.source?.cancel()
                self.source = nil
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                    self?.start()
                    self?.notifyIfNotSuppressed()
                }
            } else {
                self.notifyIfNotSuppressed()
            }
        }
        src.setCancelHandler { close(fd) }
        source = src
        src.resume()
    }

    private func notifyIfNotSuppressed() {
        guard Date() >= suppressUntil else { return }
        notify()
    }

    private func notify() {
        guard !stopped else { return }
        let handler = onEvent
        // Pequeño retraso para dejar terminar la escritura externa.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            Task { @MainActor in handler() }
        }
    }

    deinit {
        source?.cancel()
    }
}
