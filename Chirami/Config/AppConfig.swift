import Foundation
import os

class AppConfig: YAMLStore<ChiramiConfig> {
    static let shared = AppConfig()

    private let logger = Logger(subsystem: "io.github.uphy.Chirami", category: "AppConfig")
    var config: ChiramiConfig { data }

    private init() {
        let configDir = FileManager.realHomeDirectory
            .appendingPathComponent(".config/chirami")
        Self.initializeIfNeeded(configDir: configDir)
        super.init(directory: configDir, fileName: "config.yaml", label: "Config", defaultValue: ChiramiConfig(), watchForChanges: true)
    }

    private static func initializeIfNeeded(configDir: URL) {
        let configFile = configDir.appendingPathComponent("config.yaml")
        guard !FileManager.default.fileExists(atPath: configFile.path) else { return }

        let sampleNotesDir = configDir.appendingPathComponent("sample-notes")
        let dailyDir = sampleNotesDir.appendingPathComponent("daily")

        do {
            try FileManager.default.createDirectory(at: sampleNotesDir, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: dailyDir, withIntermediateDirectories: true)

            try welcomeContent.write(to: sampleNotesDir.appendingPathComponent("welcome.md"), atomically: true, encoding: .utf8)
            try quickMemoContent.write(to: sampleNotesDir.appendingPathComponent("quick-memo.md"), atomically: true, encoding: .utf8)
            try dailyTemplateContent.write(to: dailyDir.appendingPathComponent("template.md"), atomically: true, encoding: .utf8)

            // Generate daily notes for the past 3 days
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
            for daysAgo in 1...3 {
                let date = Calendar.current.date(byAdding: .day, value: -daysAgo, to: Date())!
                let dateString = formatter.string(from: date)
                let content = makeDailyContent(dateString: dateString, daysAgo: daysAgo)
                try content.write(to: dailyDir.appendingPathComponent("\(dateString).md"), atomically: true, encoding: .utf8)
            }

            try configYAMLContent.write(to: configFile, atomically: true, encoding: .utf8)
        } catch {
            Logger(subsystem: "io.github.uphy.Chirami", category: "AppConfig").error("AppConfig initialization error: \(error, privacy: .public)")
        }
    }

    // MARK: - Sample Content

    private static let configYAMLContent = """
    notes:
      - path: ~/.config/chirami/sample-notes/welcome.md
        title: Welcome
        color_scheme: yellow

      - path: ~/.config/chirami/sample-notes/quick-memo.md
        title: Quick Memo
        color_scheme: blue
        position: cursor
        hotkey: cmd+shift+m

      - path: ~/.config/chirami/sample-notes/daily/{yyyy-MM-dd}.md
        title: Daily Note
        color_scheme: green
        template: ~/.config/chirami/sample-notes/daily/template.md
    """

    private static let welcomeContent = """
    # Welcome to Chirami

    A quick reference for Chirami.

    ## Basic Usage

    - **Move**: Drag the title bar to reposition it (hold `Cmd` to drag from anywhere)
    - **Menu bar**: Manage notes from the menu bar icon
    - **Add notes**: Edit `config.yaml` via Menu → "Edit Config"

    ## Show / Hide Notes

    Click a note in the **menu bar popup** to toggle its visibility.

    You can also assign a keyboard shortcut to each note via the `hotkey` field in `config.yaml`.
    In this demo, **Quick Memo** is set to `Cmd+Shift+M` — try pressing it!

    ## Markdown

    **bold** / *italic* / `code`

    - [ ] Unchecked task
    - [x] Checked task

    [Chirami GitHub](https://github.com/uphy/chirami)

    ## Config File

    Edit `~/.config/chirami/config.yaml` to customize Chirami.
    """

    private static let quickMemoContent = """
    # Quick Memo

    Write something...

    ---
    This note is configured with (`config.yaml`):

    - **`hotkey: cmd+shift+m`** — summon/dismiss with a keyboard shortcut
    - **`position: cursor`** — appears at the mouse cursor position when summoned

    Cursor notes start unpinned by default — they hide when focus is lost.
    Click the pin button to keep them visible.

    These can be customized in `config.yaml`.
    """

    private static let emptyTask = "- [ ] "

    private static let dailyTemplateContent = """
    ## How to Use Daily Notes

    A daily note is created per day and saved as a separate file.

    **Navigation (title bar)**

    - `<` — Go to previous day
    - `>` — Go to next day
    - `⏭` — Return to today (shown only when viewing a past note)

    ## Today's Tasks

    \(emptyTask)
    \(emptyTask)
    \(emptyTask)

    ## Notes

    ## Done

    -
    """

    private static func makeDailyContent(dateString: String, daysAgo: Int) -> String {
        let taskSets = [
            ["Code review", "Update docs", "Fix bug"],
            ["Prepare meeting", "Design review", "Write tests"],
            ["Set up environment", "Clarify spec", "Implement"]
        ]
        let notes = [
            "Good progress today.",
            "Got stuck briefly but resolved it.",
            "Some items carried over to tomorrow."
        ]
        let idx = (daysAgo - 1) % taskSets.count
        let tasks = taskSets[idx]
        return """
        ## Today's Tasks

        - [x] \(tasks[0])
        - [x] \(tasks[1])
        - [ ] \(tasks[2])

        ## Notes

        \(notes[idx])

        ## Done

        - \(tasks[0])
        - \(tasks[1])
        """
    }
}
