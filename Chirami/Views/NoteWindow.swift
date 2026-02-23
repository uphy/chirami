import AppKit
import SwiftUI
import Combine

// MARK: - NoteWindowController

/// Manages a single note window: position/size persistence, transparency, always-on-top.
@MainActor
class NoteWindowController: NSWindowController, NSWindowDelegate {
    private(set) var note: Note
    private let noteStore = NoteStore.shared
    private var fileWatcher: FileWatcher?
    private var contentModel: NoteContentModel
    private var cancellables = Set<AnyCancellable>()
    private var isShowingToday: Bool = true

    var isVisible: Bool { window?.isVisible ?? false }

    init(note: Note) {
        self.note = note
        self.contentModel = NoteContentModel(note: note)

        let savedState = NoteStore.shared.windowState(for: note)
        let frame = CGRect(
            origin: savedState?.cgPoint ?? CGPoint(x: 100, y: 200),
            size: savedState?.cgSize ?? CGSize(width: 300, height: 400)
        )

        let panel = NotePanel(
            contentRect: frame,
            styleMask: [.titled, .closable, .resizable, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        panel.title = note.title
        panel.titlebarAppearsTransparent = true
        panel.titleVisibility = .visible
        panel.isMovableByWindowBackground = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.level = note.alwaysOnTop ? .floating : .normal
        panel.alphaValue = note.transparency
        panel.backgroundColor = note.color.nsColor

        // Minimal toolbar: just the close button
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true
        panel.setupCloseButtonHover()
        panel.centerTitle()

        super.init(window: panel)
        panel.delegate = self

        if note.periodicInfo != nil {
            panel.setupNavigationButtons(
                target: self,
                prevAction: #selector(navigatePreviousAction),
                nextAction: #selector(navigateNextAction),
                todayAction: #selector(navigateToTodayAction)
            )
            updateNavigationButtons()
        }

        let rootView = NoteContentView(model: contentModel, noteId: note.id)
            .environmentObject(NoteStore.shared)
        panel.contentView = NSHostingView(rootView: rootView)

        setupFileWatcher()

        // Subscribe to note changes to keep panel background and title in sync
        let noteId = note.id
        NoteStore.shared.$notes
            .dropFirst()
            .sink { notes in
                guard let updated = notes.first(where: { $0.id == noteId }) else { return }
                Task { @MainActor [weak self] in
                    self?.applyNoteUpdate(updated)
                }
            }
            .store(in: &cancellables)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    // MARK: - Visibility

    func showIfNeeded() {
        let visible = noteStore.isVisible(note)
        if visible {
            showWindow(nil)
        }
    }

    func show() {
        if note.position == .cursor {
            showAtCursor()
        } else {
            showWindow(nil)
        }
        noteStore.setVisible(true, for: note)
    }

    private func showAtCursor() {
        guard let window = window else { return }

        let cursorLocation = NSEvent.mouseLocation
        let windowSize = window.frame.size

        let screen = screenForCursor() ?? NSScreen.main
        let visibleFrame = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1920, height: 1080)

        // Place window centered on cursor position
        // NSWindow origin is bottom-left corner
        let origin = CGPoint(x: cursorLocation.x - windowSize.width / 2, y: cursorLocation.y - windowSize.height / 2)
        let clamped = clampToScreen(origin: origin, windowSize: windowSize, visibleFrame: visibleFrame)

        window.setFrameOrigin(clamped)
        showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    private func screenForCursor() -> NSScreen? {
        let cursorLocation = NSEvent.mouseLocation
        for screen in NSScreen.screens where NSMouseInRect(cursorLocation, screen.frame, false) {
            return screen
        }
        return NSScreen.main
    }

    private func clampToScreen(origin: CGPoint, windowSize: CGSize, visibleFrame: CGRect) -> CGPoint {
        var x = origin.x
        var y = origin.y

        // Clamp right edge
        if x + windowSize.width > visibleFrame.maxX {
            x = visibleFrame.maxX - windowSize.width
        }
        // Clamp left edge
        if x < visibleFrame.minX {
            x = visibleFrame.minX
        }
        // Clamp bottom edge
        if y < visibleFrame.minY {
            y = visibleFrame.minY
        }
        // Clamp top edge (origin is bottom-left, so top = y + height)
        if y + windowSize.height > visibleFrame.maxY {
            y = visibleFrame.maxY - windowSize.height
        }

        return CGPoint(x: x, y: y)
    }

    func hide() {
        window?.orderOut(nil)
        noteStore.setVisible(false, for: note)
    }

    func toggle() {
        if isVisible { hide() } else { show() }
    }

    // MARK: - Note updates

    private func applyNoteUpdate(_ updated: Note) {
        guard let panel = window as? NotePanel else { return }
        panel.backgroundColor = updated.color.nsColor
        panel.alphaValue = updated.transparency
        panel.title = updated.title
        panel.level = updated.alwaysOnTop ? .floating : .normal
        contentModel.fontSize = updated.fontSize
        note.position = updated.position
        note.autoHide = updated.autoHide
    }

    // MARK: - NSWindowDelegate

    func windowDidResignKey(_ notification: Notification) {
        guard note.autoHide, isVisible else { return }
        contentModel.save()
        hide()
    }

    func windowWillClose(_ notification: Notification) {
        guard let window = window else { return }
        noteStore.saveWindowState(
            for: note,
            position: window.frame.origin,
            size: window.frame.size,
            visible: false
        )
    }

    func windowDidMove(_ notification: Notification) {
        if note.position != .cursor {
            saveWindowState()
        }
    }

    func windowDidResize(_ notification: Notification) {
        if note.position == .cursor {
            // Save size only: read existing position from state
            guard let window = window else { return }
            let existingPosition = noteStore.windowState(for: note)?.cgPoint ?? window.frame.origin
            noteStore.saveWindowState(
                for: note,
                position: existingPosition,
                size: window.frame.size,
                visible: isVisible
            )
        } else {
            saveWindowState()
        }
    }

    private func saveWindowState() {
        guard let window = window else { return }
        noteStore.saveWindowState(
            for: note,
            position: window.frame.origin,
            size: window.frame.size,
            visible: isVisible
        )
    }

    // MARK: - Periodic Note Navigation

    @objc private func navigatePreviousAction() { navigatePrevious() }
    @objc private func navigateNextAction() { navigateNext() }
    @objc private func navigateToTodayAction() { navigateToToday() }

    func navigatePrevious() {
        guard let info = note.periodicInfo else { return }
        let baseDir = PathTemplateResolver.extractBaseDirectory(from: info.pathTemplate)
        guard let baseDirURL = resolveTemplatePath(baseDir) else { return }
        let relativeTemplate = String(info.pathTemplate.dropFirst(baseDir.count))
        let files = PeriodicFileNavigator.listMatchingFiles(template: relativeTemplate, baseDirectory: baseDirURL)
        guard let prev = PeriodicFileNavigator.previousFile(from: note.path, in: files) else { return }
        navigateToFile(prev)
    }

    func navigateNext() {
        guard let info = note.periodicInfo else { return }
        let baseDir = PathTemplateResolver.extractBaseDirectory(from: info.pathTemplate)
        guard let baseDirURL = resolveTemplatePath(baseDir) else { return }
        let relativeTemplate = String(info.pathTemplate.dropFirst(baseDir.count))
        let files = PeriodicFileNavigator.listMatchingFiles(template: relativeTemplate, baseDirectory: baseDirURL)
        guard let next = PeriodicFileNavigator.nextFile(from: note.path, in: files) else { return }
        navigateToFile(next)
    }

    func navigateToToday() {
        guard let info = note.periodicInfo else { return }
        let config = NoteConfig(path: info.pathTemplate, template: info.templateFile?.path)
        let date = noteStore.logicalDate(rolloverDelay: info.rolloverDelay)
        guard let newNote = noteStore.resolvePeriodicNote(from: config, for: date) else { return }
        navigateToFile(newNote.path)
        isShowingToday = true
        updateNavigationButtons()
    }

    func handleRollover(_ newNote: Note) {
        guard isShowingToday else { return }
        note.path = newNote.path
        note.title = newNote.title
        reloadContentForNavigation()
    }

    private func navigateToFile(_ url: URL) {
        note.path = url
        // Update title
        if let info = note.periodicInfo {
            let fileName = url.deletingPathExtension().lastPathComponent
            if let prefix = info.titlePrefix {
                note.title = "\(prefix) — \(fileName)"
            } else {
                note.title = fileName
            }
        }
        isShowingToday = false
        // Check if navigated file is actually today's file
        if let info = note.periodicInfo {
            let todayPath = PathTemplateResolver.resolve(info.pathTemplate, for: noteStore.logicalDate(rolloverDelay: info.rolloverDelay))
            if let todayURL = resolveTemplatePath(todayPath), todayURL.path == url.path {
                isShowingToday = true
            }
        }
        reloadContentForNavigation()
    }

    private func reloadContentForNavigation() {
        // Create file if needed
        if !FileManager.default.fileExists(atPath: note.path.path) {
            noteStore.writeContent("", to: note)
        }

        contentModel = NoteContentModel(note: note)
        let rootView = NoteContentView(model: contentModel, noteId: note.id)
            .environmentObject(NoteStore.shared)
        (window as? NotePanel)?.contentView = NSHostingView(rootView: rootView)

        // Update panel title
        (window as? NotePanel)?.title = note.title

        // Restart file watcher
        setupFileWatcher()

        updateNavigationButtons()
    }

    private func updateNavigationButtons() {
        guard let panel = window as? NotePanel, let info = note.periodicInfo else { return }
        let baseDir = PathTemplateResolver.extractBaseDirectory(from: info.pathTemplate)
        guard let baseDirURL = resolveTemplatePath(baseDir) else { return }
        let relativeTemplate = String(info.pathTemplate.dropFirst(baseDir.count))
        let files = PeriodicFileNavigator.listMatchingFiles(template: relativeTemplate, baseDirectory: baseDirURL)
        let hasPrev = PeriodicFileNavigator.previousFile(from: note.path, in: files) != nil
        let hasNext = PeriodicFileNavigator.nextFile(from: note.path, in: files) != nil
        panel.updateNavigationState(hasPrevious: hasPrev, hasNext: hasNext, isToday: isShowingToday)
    }

    private func resolveTemplatePath(_ path: String) -> URL? {
        if path.hasPrefix("~/") {
            return FileManager.realHomeDirectory.appendingPathComponent(String(path.dropFirst(2)))
        }
        return URL(fileURLWithPath: path)
    }

    // MARK: - File watching

    private func setupFileWatcher() {
        // Create the file if it doesn't exist
        if !FileManager.default.fileExists(atPath: note.path.path) {
            noteStore.writeContent("", to: note)
        }

        fileWatcher = FileWatcher(url: note.path) { [weak self] in
            Task { @MainActor [weak self] in
                self?.reloadContent()
            }
        }
    }

    private func reloadContent() {
        let newContent = noteStore.readContent(of: note)
        contentModel.reloadIfNeeded(newContent)
    }
}

// MARK: - NoteContentModel

/// Shared state between NoteWindowController and NoteContentView.
@MainActor
class NoteContentModel: ObservableObject {
    @Published var text: String = ""
    @Published var fontSize: CGFloat
    private let note: Note
    private var isSaving = false
    private var isReloading = false
    private var lastSavedContent: String = ""

    init(note: Note) {
        self.note = note
        self.fontSize = note.fontSize
        let content = NoteStore.shared.readContent(of: note)
        text = content
        lastSavedContent = content
    }

    func save() {
        guard !isSaving, !isReloading, text != lastSavedContent else { return }
        isSaving = true
        lastSavedContent = text
        NoteStore.shared.writeContent(text, to: note)
        isSaving = false
    }

    func reloadIfNeeded(_ newContent: String) {
        guard !isSaving, newContent != text else { return }
        isReloading = true
        lastSavedContent = newContent
        text = newContent
        isReloading = false
    }
}

// MARK: - NoteContentView

struct NoteContentView: View {
    @ObservedObject var model: NoteContentModel
    let noteId: String
    @State private var showColorPicker = false
    @EnvironmentObject private var noteStore: NoteStore

    private var note: Note? {
        noteStore.notes.first(where: { $0.id == noteId })
    }

    var body: some View {
        LivePreviewEditor(
            text: $model.text,
            backgroundColor: note?.color.nsColor ?? NoteColor.yellow.nsColor,
            noteColor: note?.color ?? .yellow,
            fontSize: model.fontSize,
            onFontSizeChange: { newSize in
                model.fontSize = newSize
            },
            customMenuItems: { [weak noteStore] in
                var items: [NSMenuItem] = []
                guard let noteStore, let note = noteStore.notes.first(where: { $0.id == noteId }) else {
                    return items
                }
                let isOnTop = note.alwaysOnTop
                let alwaysOnTopItem = NSMenuItem(
                    title: "Always on Top",
                    action: #selector(NoteMenuActions.toggleAlwaysOnTop(_:)),
                    keyEquivalent: ""
                )
                alwaysOnTopItem.state = isOnTop ? .on : .off
                alwaysOnTopItem.representedObject = note
                alwaysOnTopItem.target = NoteMenuActions.shared
                items.append(alwaysOnTopItem)

                let colorItem = NSMenuItem(
                    title: "Change Color...",
                    action: #selector(NoteMenuActions.changeColor(_:)),
                    keyEquivalent: ""
                )
                colorItem.representedObject = NoteMenuContext(noteId: noteId, showColorPicker: $showColorPicker)
                colorItem.target = NoteMenuActions.shared
                items.append(colorItem)
                return items
            }
        )
        .onChange(of: model.text) { _, _ in
            model.save()
        }
        .popover(isPresented: $showColorPicker) {
            if let note {
                ColorPickerView(note: note)
            }
        }
        .background((note?.color.nsColor ?? NoteColor.yellow.nsColor).swiftUI)
    }
}

// MARK: - ColorPickerView

struct ColorPickerView: View {
    let note: Note
    @Environment(\.dismiss) private var dismiss
    @State private var transparency: Double

    init(note: Note) {
        self.note = note
        self._transparency = State(initialValue: note.transparency)
    }

    var body: some View {
        VStack(spacing: 8) {
            Text("Note Color")
                .font(.headline)
            HStack(spacing: 8) {
                ForEach(NoteColor.allCases, id: \.rawValue) { color in
                    Button {
                        NoteStore.shared.updateColor(color, for: note)
                        dismiss()
                    } label: {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(color.nsColor.swiftUI)
                            .frame(width: 24, height: 24)
                            .overlay(
                                RoundedRectangle(cornerRadius: 4)
                                    .stroke(Color.secondary, lineWidth: note.color == color ? 2 : 0.5)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }

            Divider()

            VStack(spacing: 4) {
                Text("Transparency")
                    .font(.subheadline)
                HStack {
                    Slider(value: $transparency, in: 0.3...1.0, step: 0.05)
                        .frame(width: 150)
                    Text("\(Int(transparency * 100))%")
                        .font(.caption)
                        .monospacedDigit()
                        .frame(width: 36, alignment: .trailing)
                }
            }
            .onChange(of: transparency) { _, newValue in
                NoteStore.shared.updateTransparency(newValue, for: note)
            }
        }
        .padding()
    }
}

// MARK: - Context Menu Actions

struct NoteMenuContext {
    let noteId: String
    let showColorPicker: Binding<Bool>
}

class NoteMenuActions: NSObject {
    static let shared = NoteMenuActions()

    @MainActor @objc func toggleAlwaysOnTop(_ sender: NSMenuItem) {
        guard let note = sender.representedObject as? Note else { return }
        NoteStore.shared.updateAlwaysOnTop(!note.alwaysOnTop, for: note)
    }

    @MainActor @objc func changeColor(_ sender: NSMenuItem) {
        guard let context = sender.representedObject as? NoteMenuContext else { return }
        context.showColorPicker.wrappedValue = true
    }
}
