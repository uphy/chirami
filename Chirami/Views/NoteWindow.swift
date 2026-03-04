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
    private var isPinned: Bool
    private var isFadingOut: Bool = false
    private var fadeOutToken: Int = 0

    var isVisible: Bool { window?.isVisible ?? false }

    init(note: Note) {
        self.note = note
        self.isPinned = NoteStore.shared.isPinned(note)
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
        panel.isRestorable = false

        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true
        panel.setupCloseButtonHover()
        panel.centerTitle()

        super.init(window: panel)
        panel.delegate = self
        panel.onWarpKey = { [weak self] key in
            self?.warpTo(key: key)
        }
        panel.onHideRequest = { [weak self] in
            self?.hide()
        }

        if note.periodicInfo != nil {
            panel.setupNavigationButtons(
                target: self,
                prevAction: #selector(navigatePrevious),
                nextAction: #selector(navigateNext),
                todayAction: #selector(navigateToToday)
            )
            updateNavigationButtons()
        }

        panel.setupPinButton(target: self, action: #selector(togglePinAction))
        panel.updatePinState(isPinned: isPinned)

        let rootView = NoteContentView(model: contentModel, noteId: note.id, onTogglePin: { [weak self] in self?.togglePinAction() })
            .environmentObject(NoteStore.shared)
        panel.contentView = NSHostingView(rootView: rootView)

        setupFileWatcher()

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
        guard let panel = window as? NotePanel else { return }

        // Switch to today's note if the date has changed while the window was hidden
        if note.periodicInfo != nil, isShowingToday {
            navigateToTodayIfNeeded()
        }

        // Cancel in-flight fade-out
        isFadingOut = false
        fadeOutToken += 1

        if !panel.isVisible {
            panel.alphaValue = 0
            if note.position == .cursor {
                showAtCursor()
            } else {
                showWindow(nil)
            }
        } else {
            // Mid-fade-out: window is still visible, reset alpha for fade-in
            panel.alphaValue = 0
        }

        if NotePanel.startupMode {
            // Startup path: show without stealing keyboard focus.
            panel.orderFront(nil)
        } else {
            // Always make key explicitly. showWindow(nil) calls orderFront (not
            // makeKeyAndOrderFront) for floating panels, so becomeKey never fires.
            panel.makeKeyAndOrderFront(nil)
        }

        noteStore.setVisible(true, for: note)

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            panel.animator().alphaValue = note.transparency
        }
    }

    private func showAtCursor() {
        guard let window = window else { return }

        let cursorLocation = NSEvent.mouseLocation
        let windowSize = window.frame.size

        let screen = screenForCursor() ?? NSScreen.main
        let visibleFrame = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1920, height: 1080)

        let origin = CGPoint(x: cursorLocation.x - windowSize.width / 2, y: cursorLocation.y - windowSize.height / 2)
        let clamped = clampToScreen(origin: origin, windowSize: windowSize, visibleFrame: visibleFrame)

        window.setFrameOrigin(clamped)
        showWindow(nil)
        window.orderFront(nil)
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

        if x + windowSize.width > visibleFrame.maxX {
            x = visibleFrame.maxX - windowSize.width
        }
        if x < visibleFrame.minX {
            x = visibleFrame.minX
        }
        if y < visibleFrame.minY {
            y = visibleFrame.minY
        }
        if y + windowSize.height > visibleFrame.maxY {
            y = visibleFrame.maxY - windowSize.height
        }

        return CGPoint(x: x, y: y)
    }

    func hide() {
        guard let panel = window as? NotePanel else { return }

        saveEditorState()

        isFadingOut = true
        let token = fadeOutToken
        let targetTransparency = note.transparency

        noteStore.setVisible(false, for: note)

        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.2
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self, self.isFadingOut, self.fadeOutToken == token else { return }
                self.isFadingOut = false
                panel.orderOut(nil)
                panel.alphaValue = targetTransparency  // Restore for next show()
            }
        })
    }

    func saveEditorState() {
        AppState.shared.updateEditorState(
            for: note.id,
            cursorPosition: contentModel.savedCursorLocation,
            scrollOffset: contentModel.savedScrollOffset
        )
    }

    /// Returns the current editor state for batch persistence.
    var editorStateSnapshot: (noteId: String, cursorPosition: Int, scrollOffset: CGPoint) {
        (note.id, contentModel.savedCursorLocation, contentModel.savedScrollOffset)
    }

    func toggle() {
        if isVisible {
            if window?.isKeyWindow == true {
                hide()
            } else {
                window?.makeKeyAndOrderFront(nil)
            }
        } else {
            show()
        }
    }

    // MARK: - Note updates

    private func applyNoteUpdate(_ updated: Note) {
        guard let panel = window as? NotePanel else { return }
        panel.backgroundColor = updated.color.nsColor
        // Skip alpha update during fade-out to avoid interrupting animation
        if !isFadingOut {
            panel.alphaValue = updated.transparency
        }
        panel.title = updated.title
        panel.level = updated.alwaysOnTop ? .floating : .normal
        contentModel.fontSize = updated.fontSize
        note.position = updated.position
        note.transparency = updated.transparency  // Keep in sync for fade-in target
    }

    // MARK: - NSWindowDelegate

    func windowDidResignKey(_ notification: Notification) {
        guard !isPinned, isVisible else { return }
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

    // MARK: - Keyboard Warp

    /// Warp the window to the adjacent grid position in the given HJKL direction, cycling at edges.
    func warpTo(key: Character) {
        guard let window = window else { return }
        let screen = screenForWindow() ?? NSScreen.main
        guard let visibleFrame = screen?.visibleFrame else { return }

        let center = CGPoint(
            x: window.frame.midX,
            y: window.frame.midY
        )
        let (col, row) = inferGridPosition(center: center, visibleFrame: visibleFrame)
        let (newCol, newRow) = applyMove(key: key, col: col, row: row)
        let origin = gridOrigin(col: newCol, row: newRow, windowSize: window.frame.size, visibleFrame: visibleFrame)
        let newFrame = CGRect(origin: origin, size: window.frame.size)
        window.setFrame(newFrame, display: true, animate: true)
    }

    /// Returns the screen whose visible area contains the window's center point.
    private func screenForWindow() -> NSScreen? {
        guard let window = window else { return NSScreen.main }
        let center = CGPoint(x: window.frame.midX, y: window.frame.midY)
        for screen in NSScreen.screens where screen.frame.contains(center) {
            return screen
        }
        return NSScreen.main
    }

    /// Maps the window center to the nearest 3x3 grid cell using band detection.
    /// col: 0=left, 1=center, 2=right / row: 0=bottom, 1=center, 2=top (NSWindow bottom-left origin)
    private func inferGridPosition(center: CGPoint, visibleFrame: CGRect) -> (col: Int, row: Int) {
        let col = Int(min(2, max(0, (center.x - visibleFrame.minX) / (visibleFrame.width / 3))))
        let row = Int(min(2, max(0, (center.y - visibleFrame.minY) / (visibleFrame.height / 3))))
        return (col, row)
    }

    /// Applies an HJKL move to grid coordinates with cyclic wrapping.
    private func applyMove(key: Character, col: Int, row: Int) -> (col: Int, row: Int) {
        switch key {
        case "h": return ((col + 2) % 3, row)
        case "l": return ((col + 1) % 3, row)
        case "k": return (col, (row + 1) % 3)
        case "j": return (col, (row + 2) % 3)
        default:  return (col, row)
        }
    }

    /// Calculates the window origin for a grid cell, with an 8pt margin from screen edges.
    private func gridOrigin(col: Int, row: Int, windowSize: CGSize, visibleFrame: CGRect) -> CGPoint {
        let margin: CGFloat = 8
        let x: CGFloat
        switch col {
        case 0:  x = visibleFrame.minX + margin
        case 2:  x = visibleFrame.maxX - windowSize.width - margin
        default: x = visibleFrame.midX - windowSize.width / 2
        }
        let y: CGFloat
        switch row {
        case 0:  y = visibleFrame.minY + margin
        case 2:  y = visibleFrame.maxY - windowSize.height - margin
        default: y = visibleFrame.midY - windowSize.height / 2
        }
        return CGPoint(x: x, y: y)
    }

    // MARK: - Pin

    @objc func togglePinAction() {
        isPinned.toggle()
        (window as? NotePanel)?.updatePinState(isPinned: isPinned)
        noteStore.setPinned(isPinned, for: note)
    }

    // MARK: - Periodic Note Navigation

    @objc func navigatePrevious() {
        guard let info = note.periodicInfo else { return }
        let baseDir = PathTemplateResolver.extractBaseDirectory(from: info.pathTemplate)
        guard let baseDirURL = resolveTemplatePath(baseDir) else { return }
        let relativeTemplate = String(info.pathTemplate.dropFirst(baseDir.count))
        let files = PeriodicFileNavigator.listMatchingFiles(template: relativeTemplate, baseDirectory: baseDirURL)
        guard let prev = PeriodicFileNavigator.previousFile(from: note.path, in: files) else { return }
        navigateToFile(prev)
    }

    @objc func navigateNext() {
        guard let info = note.periodicInfo else { return }
        let baseDir = PathTemplateResolver.extractBaseDirectory(from: info.pathTemplate)
        guard let baseDirURL = resolveTemplatePath(baseDir) else { return }
        let relativeTemplate = String(info.pathTemplate.dropFirst(baseDir.count))
        let files = PeriodicFileNavigator.listMatchingFiles(template: relativeTemplate, baseDirectory: baseDirURL)
        guard let next = PeriodicFileNavigator.nextFile(from: note.path, in: files) else { return }
        navigateToFile(next)
    }

    /// Navigate to today's periodic note only if the date has changed.
    /// Skips model recreation when the path hasn't changed (preserves cursor/scroll).
    private func navigateToTodayIfNeeded() {
        resolveAndNavigateToToday(force: false)
    }

    @objc func navigateToToday() {
        resolveAndNavigateToToday(force: true)
    }

    private func resolveAndNavigateToToday(force: Bool) {
        guard let info = note.periodicInfo else { return }
        let config = NoteConfig(path: info.pathTemplate, template: info.templateFile?.path)
        let date = noteStore.logicalDate(rolloverDelay: info.rolloverDelay)
        guard let newNote = noteStore.resolvePeriodicNote(from: config, for: date) else { return }
        if !force {
            guard newNote.path.path != note.path.path else { return }
        }
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
        if !FileManager.default.fileExists(atPath: note.path.path) {
            noteStore.writeContent("", to: note)
        }

        contentModel = NoteContentModel(note: note)
        let rootView = NoteContentView(model: contentModel, noteId: note.id, onTogglePin: { [weak self] in self?.togglePinAction() })
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
class NoteContentModel: ObservableObject, EditorStatePreservable {
    @Published var text: String = ""
    @Published var fontSize: CGFloat
    nonisolated(unsafe) var savedCursorLocation: Int = 0
    nonisolated(unsafe) var savedScrollOffset: CGPoint = .zero
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

        // Restore editor state from persisted window state
        if let state = AppState.shared.windowState(for: note.id) {
            savedCursorLocation = state.cursorPosition ?? 0
            savedScrollOffset = state.scrollCGPoint ?? .zero
        }
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
    var onTogglePin: (() -> Void)?
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
            fontName: AppConfig.shared.config.font,
            noteURL: note?.path,
            attachmentsDir: note?.attachmentsDir,
            editorState: model,
            onFontSizeChange: { newSize in
                model.fontSize = newSize
            },
            onTogglePin: onTogglePin,
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
