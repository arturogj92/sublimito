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
        Group(title: "Files & Notes", items: [
            Shortcut(keys: "⌘N", detail: "New note (auto-backed up, never lost)"),
            Shortcut(keys: "⌘O", detail: "Open file"),
            Shortcut(keys: "⇧⌘O", detail: "Open folder as project"),
            Shortcut(keys: "⌘S", detail: "Save"),
            Shortcut(keys: "⇧⌘S", detail: "Save As…"),
            Shortcut(keys: "⌘W", detail: "Close tab (no dialogs, recoverable from Recents)"),
            Shortcut(keys: "⇧⌘T", detail: "Reopen last closed tab"),
            Shortcut(keys: "Middle Click", detail: "Close tab with the mouse wheel, on tabs and in the sidebar"),
            Shortcut(keys: "Double Click", detail: "Rename note or file"),
        ]),
        Group(title: "Find", items: [
            Shortcut(keys: "⌘F", detail: "Find in document (with match counter)"),
            Shortcut(keys: "⌥⌘F", detail: "Find and replace"),
            Shortcut(keys: "⌘G", detail: "Find Next"),
            Shortcut(keys: "⇧⌘G", detail: "Find Previous"),
            Shortcut(keys: "⇧⌘F", detail: "Find in files (open tabs, folder or everything)"),
            Shortcut(keys: "⌘P", detail: "Go to tab, recent, or search by content"),
        ]),
        Group(title: "Editing", items: [
            Shortcut(keys: "⌘D", detail: "Add next occurrence to selection (multi-cursor)"),
            Shortcut(keys: "⌥ Click", detail: "Add cursor (multi-cursor)"),
            Shortcut(keys: "⌥⌘↑ / ↓", detail: "Add cursor above / below"),
            Shortcut(keys: "⌃G", detail: "Go to line"),
            Shortcut(keys: "⌥⌘[ / ]", detail: "Fold / unfold code block"),
        ]),
        Group(title: "View", items: [
            Shortcut(keys: "⇧⌘P", detail: "Toggle Markdown preview / raw text"),
            Shortcut(keys: "⌘B", detail: "Show or hide the sidebar"),
            Shortcut(keys: "⌘+ / ⌘−", detail: "Increase or decrease font size"),
            Shortcut(keys: "⌘0", detail: "Default font size"),
        ]),
        Group(title: "Navigation", items: [
            Shortcut(keys: "⇧⌘]", detail: "Next Tab"),
            Shortcut(keys: "⇧⌘[", detail: "Previous Tab"),
        ]),
    ]

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Keyboard Shortcuts")
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
