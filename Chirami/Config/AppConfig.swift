import Foundation

class AppConfig: YAMLStore<ChiramiConfig> {
    static let shared = AppConfig()

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

            // 過去3日分のdailyノートを生成
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
            print("AppConfig initialization error: \(error)")
        }
    }

    // MARK: - Sample Content

    private static let configYAMLContent = """
    notes:
      - path: ~/.config/chirami/sample-notes/welcome.md
        title: Welcome
        color: yellow

      - path: ~/.config/chirami/sample-notes/quick-memo.md
        title: Quick Memo
        color: blue
        position: cursor
        auto_hide: true
        hotkey: cmd+shift+m

      - path: ~/.config/chirami/sample-notes/daily/{yyyy-MM-dd}.md
        title: Daily Note
        color: green
        template: ~/.config/chirami/sample-notes/daily/template.md
    """

    private static let welcomeContent = """
    # Welcome to Chirami

    A quick reference for Chirami.

    ## Basic Usage

    - **Move**: Drag a note to reposition it
    - **Menu bar**: Manage notes from the menu bar icon
    - **Add notes**: Edit `config.yaml` via Menu → "Edit Config"

    ## Keyboard Shortcuts

    Shortcuts are fully customizable via the `hotkey` field in `config.yaml`.

    | Shortcut | Action |
    |---|---|
    | `Cmd+Shift+M` | Show/hide Quick Memo (customizable) |

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
    *Press `Cmd+Shift+M` to summon. Auto-hides on focus loss.*
    """

    private static let dailyTemplateContent = """
    ## How to Use Daily Notes

    A daily note is created per day and saved as a separate file.

    **Navigation (title bar)**

    - `<` — Go to previous day
    - `>` — Go to next day
    - `⏭` — Return to today (shown only when viewing a past note)

    ## Today's Tasks

    - [ ] 
    - [ ] 
    - [ ] 

    ## Notes

    ## Done

    -
    """

    private static func makeDailyContent(dateString: String, daysAgo: Int) -> String {
        let taskSets = [
            ["Code review", "Update docs", "Fix bug"],
            ["Prepare meeting", "Design review", "Write tests"],
            ["Set up environment", "Clarify spec", "Implement"],
        ]
        let notes = [
            "Good progress today.",
            "Got stuck briefly but resolved it.",
            "Some items carried over to tomorrow.",
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
