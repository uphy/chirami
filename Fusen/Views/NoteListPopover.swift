import ServiceManagement
import SwiftUI

struct NoteListView: View {
    @ObservedObject private var noteStore = NoteStore.shared
    private let windowManager = WindowManager.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            Text("Fusen")
                .font(.headline)
                .padding(.horizontal, 12)
                .padding(.top, 10)
                .padding(.bottom, 6)

            Divider()

            // Note list
            if noteStore.notes.isEmpty {
                Text("No notes configured.\nEdit ~/.config/fusen/config.yaml")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(12)
            } else {
                ForEach(noteStore.notes) { note in
                    NoteRowView(note: note)
                }
            }

            Divider()

            // Actions
            VStack(spacing: 0) {
                MenuButton(title: "Show All") {
                    windowManager.showAllWindows()
                }
                MenuButton(title: "Hide All") {
                    windowManager.hideAllWindows()
                }
                MenuButton(title: "Add Note…") {
                    openFilePicker()
                }
                MenuButton(title: "Edit Config") {
                    openConfig()
                }
            }

            Divider()

            MenuToggleButton(
                title: "Launch at Login",
                isOn: SMAppService.mainApp.status == .enabled
            ) { enabled in
                do {
                    if enabled {
                        try SMAppService.mainApp.register()
                    } else {
                        try SMAppService.mainApp.unregister()
                    }
                } catch {
                    print("Failed to update login item: \(error)")
                }
            }

            Divider()

            MenuButton(title: "Quit Fusen") {
                NSApplication.shared.terminate(nil)
            }
        }
        .frame(minWidth: 220)
    }

    private func openFilePicker() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.plainText]
        panel.canCreateDirectories = true
        panel.message = "Select or create a Markdown file"
        panel.prompt = "Add Note"
        if panel.runModal() == .OK, let url = panel.url {
            noteStore.addNote(path: url)
            if let addedNote = noteStore.notes.last {
                noteStore.saveBookmark(for: addedNote.id, url: url)
            }
            windowManager.reloadWindows()
        }
    }

    private func openConfig() {
        let url = FileManager.realHomeDirectory
            .appendingPathComponent(".config/fusen/config.yaml")
        // Create default config if missing
        if !FileManager.default.fileExists(atPath: url.path) {
            let defaultConfig = """
            notes: []
            """
            try? defaultConfig.write(to: url, atomically: true, encoding: .utf8)
        }
        NSWorkspace.shared.open(url)
    }

}

// MARK: - NoteRowView

struct NoteRowView: View {
    let note: Note
    @State private var isVisible: Bool = true
    private let windowManager = WindowManager.shared

    var body: some View {
        Button {
            windowManager.toggleWindow(for: note.id)
            isVisible = windowManager.isVisible(noteId: note.id)
        } label: {
            HStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 3)
                    .fill(note.color.nsColor.swiftUI)
                    .frame(width: 12, height: 12)
                    .overlay(
                        RoundedRectangle(cornerRadius: 3)
                            .stroke(Color.secondary.opacity(0.4), lineWidth: 0.5)
                    )

                Text(note.title)
                    .font(.system(size: 13))

                Spacer()

                if windowManager.isVisible(noteId: note.id) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
            }
            .contentShape(Rectangle())
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
        }
        .buttonStyle(.plain)
        .background(Color.clear)
        .hoverEffect()
    }
}

// MARK: - MenuButton

struct MenuButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13))
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
        }
        .buttonStyle(.plain)
        .hoverEffect()
    }
}

// MARK: - MenuToggleButton

struct MenuToggleButton: View {
    let title: String
    let isOn: Bool
    let onToggle: (Bool) -> Void

    var body: some View {
        Button {
            onToggle(!isOn)
        } label: {
            HStack {
                Text(title)
                    .font(.system(size: 13))
                Spacer()
                if isOn {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
            }
            .contentShape(Rectangle())
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
        }
        .buttonStyle(.plain)
        .hoverEffect()
    }
}

// MARK: - Hover effect

private extension View {
    func hoverEffect() -> some View {
        self.modifier(HoverEffectModifier())
    }
}

private struct HoverEffectModifier: ViewModifier {
    @State private var isHovered = false

    func body(content: Content) -> some View {
        content
            .background(isHovered ? Color.accentColor.opacity(0.1) : Color.clear)
            .onHover { isHovered = $0 }
    }
}

private extension NSColor {
    var swiftUI: Color { Color(self) }
}
