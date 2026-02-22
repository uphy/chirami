import AppKit
import SwiftUI
import Combine

// MARK: - NotePanel

/// A floating NSPanel with minimal chrome for displaying a note.
class NotePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    private var closeButtonTrackingArea: NSTrackingArea?
    private var customTitleLabel: NSTextField?

    override var title: String {
        didSet { customTitleLabel?.stringValue = title }
    }

    override func becomeKey() {
        super.becomeKey()
        // NSHostingView doesn't forward first responder to embedded NSTextViews.
        // Walk the view hierarchy to find and focus the text view.
        if let textView = contentView?.firstDescendant(of: MarkdownTextView.self) {
            makeFirstResponder(textView)
        }
    }

    /// Hide the system title and add a custom centered label in the titlebar.
    func centerTitle() {
        titleVisibility = .hidden

        guard let closeButton = standardWindowButton(.closeButton) else { return }

        // Walk up from the close button to find the full-width titlebar view
        var fullWidthView: NSView = closeButton
        while let parent = fullWidthView.superview {
            fullWidthView = parent
            if parent.frame.width >= frame.width - 1 { break }
        }

        let label = NSTextField(labelWithString: title)
        label.alignment = .center
        label.font = .titleBarFont(ofSize: NSFont.systemFontSize(for: .small))
        label.textColor = .secondaryLabelColor
        label.lineBreakMode = .byTruncatingTail
        label.translatesAutoresizingMaskIntoConstraints = false

        fullWidthView.addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: fullWidthView.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: closeButton.centerYAnchor),
            label.widthAnchor.constraint(lessThanOrEqualTo: fullWidthView.widthAnchor, constant: -60),
        ])

        customTitleLabel = label
    }

    /// Hide the close button by default and show it on titlebar hover.
    func setupCloseButtonHover() {
        guard let closeButton = standardWindowButton(.closeButton),
              let titlebarView = closeButton.superview else { return }

        closeButton.alphaValue = 0

        let trackingArea = NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        titlebarView.addTrackingArea(trackingArea)
        closeButtonTrackingArea = trackingArea
    }

    override func mouseEntered(with event: NSEvent) {
        guard let closeButton = standardWindowButton(.closeButton) else {
            super.mouseEntered(with: event)
            return
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.15
            closeButton.animator().alphaValue = 1
        }
    }

    override func mouseExited(with event: NSEvent) {
        guard let closeButton = standardWindowButton(.closeButton) else {
            super.mouseExited(with: event)
            return
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.15
            closeButton.animator().alphaValue = 0
        }
    }
}

private extension NSView {
    func firstDescendant<T: NSView>(of type: T.Type) -> T? {
        for subview in subviews {
            if let match = subview as? T { return match }
            if let found = subview.firstDescendant(of: type) { return found }
        }
        return nil
    }
}

// MARK: - NoteWindowController

/// Manages a single note window: position/size persistence, transparency, always-on-top.
@MainActor
class NoteWindowController: NSWindowController, NSWindowDelegate {
    let note: Note
    private let noteStore = NoteStore.shared
    private var fileWatcher: FileWatcher?
    private var contentModel: NoteContentModel
    private var cancellables = Set<AnyCancellable>()

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
        showWindow(nil)
        noteStore.setVisible(true, for: note)
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
    }

    // MARK: - NSWindowDelegate

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
        saveWindowState()
    }

    func windowDidResize(_ notification: Notification) {
        saveWindowState()
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
