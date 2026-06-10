import AppKit
import UniformTypeIdentifiers

let home = FileManager.default.homeDirectoryForCurrentUser
let app = home.appendingPathComponent("Applications/Sublimito.app")
var types = Set<UTType>([.plainText, .text])
if let md = UTType("net.daringfireball.markdown") { types.insert(md) }
for ext in ["txt", "md", "markdown", "log", "ini", "cfg", "conf", "yaml", "yml"] {
    if let t = UTType(filenameExtension: ext) { types.insert(t) }
}
let semaphore = DispatchSemaphore(value: 0)
Task {
    for t in types {
        do {
            try await NSWorkspace.shared.setDefaultApplication(at: app, toOpen: t)
            print("\(t.identifier): OK")
        } catch {
            print("\(t.identifier): \(error.localizedDescription)")
        }
    }
    semaphore.signal()
}
semaphore.wait()
