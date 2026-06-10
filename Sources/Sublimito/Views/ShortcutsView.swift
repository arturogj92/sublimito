import SwiftUI

struct ShortcutsView: View {
    @EnvironmentObject var state: AppState

    private struct Shortcut: Identifiable {
        let id = UUID()
        let keys: String
        let detail: String
    }

    private struct Group: Identifiable {
        let id = UUID()
        let title: String
        let items: [Shortcut]
    }

    private static let groups: [Group] = [
        Group(title: "Ficheros y notas", items: [
            Shortcut(keys: "⌘N", detail: "Nueva nota (se respalda sola, nunca se pierde)"),
            Shortcut(keys: "⌘O", detail: "Abrir fichero"),
            Shortcut(keys: "⌘S", detail: "Guardar"),
            Shortcut(keys: "⇧⌘S", detail: "Guardar como…"),
            Shortcut(keys: "⌘W", detail: "Cerrar pestaña (sin diálogos, se recupera de Recientes)"),
            Shortcut(keys: "Clic central", detail: "Cerrar pestaña con la rueda, en pestañas y sidebar"),
            Shortcut(keys: "Doble clic", detail: "Renombrar nota o fichero"),
        ]),
        Group(title: "Buscar", items: [
            Shortcut(keys: "⌘F", detail: "Buscar en el documento (con contador de ocurrencias)"),
            Shortcut(keys: "⌥⌘F", detail: "Buscar y reemplazar"),
            Shortcut(keys: "⌘G", detail: "Siguiente coincidencia"),
            Shortcut(keys: "⇧⌘G", detail: "Coincidencia anterior"),
            Shortcut(keys: "⌘E", detail: "Usar selección para buscar"),
            Shortcut(keys: "⌘P", detail: "Ir a pestaña, reciente o buscar por contenido"),
        ]),
        Group(title: "Vista", items: [
            Shortcut(keys: "⇧⌘P", detail: "Alternar vista Markdown / texto raw"),
            Shortcut(keys: "⌘B", detail: "Mostrar u ocultar la barra lateral"),
            Shortcut(keys: "⌘+ / ⌘−", detail: "Aumentar o reducir la fuente"),
            Shortcut(keys: "⌘0", detail: "Tamaño de fuente por defecto"),
        ]),
        Group(title: "Navegación", items: [
            Shortcut(keys: "⇧⌘]", detail: "Pestaña siguiente"),
            Shortcut(keys: "⇧⌘[", detail: "Pestaña anterior"),
        ]),
    ]

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Atajos de teclado")
                    .font(.title3.weight(.semibold))
                Spacer()
                Button(action: { state.shortcutsShown = false }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.cancelAction)
            }
            .padding(16)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    ForEach(Self.groups) { group in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(group.title)
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.secondary)
                                .textCase(.uppercase)
                            ForEach(group.items) { item in
                                HStack(alignment: .firstTextBaseline, spacing: 12) {
                                    Text(item.keys)
                                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Color.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 5))
                                        .frame(minWidth: 92, alignment: .leading)
                                    Text(item.detail)
                                        .font(.system(size: 12))
                                    Spacer()
                                }
                            }
                        }
                    }
                }
                .padding(16)
            }
        }
        .frame(width: 480, height: 520)
    }
}
