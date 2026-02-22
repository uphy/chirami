import Darwin
import Foundation
import Yams

extension FileManager {
    static var realHomeDirectory: URL {
        if let pw = getpwuid(getuid()) {
            return URL(fileURLWithPath: String(cString: pw.pointee.pw_dir))
        }
        return FileManager.default.homeDirectoryForCurrentUser
    }
}

class YAMLStore<T: Codable>: ObservableObject {
    private let fileURL: URL
    private let label: String
    @Published private(set) var data: T

    private var fileWatcher: FileWatcher?
    private var reloadWorkItem: DispatchWorkItem?
    private var isWriting = false

    init(directory: URL, fileName: String, label: String, defaultValue: T, watchForChanges: Bool = false) {
        self.fileURL = directory.appendingPathComponent(fileName)
        self.label = label
        self.data = defaultValue

        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        load()

        if watchForChanges {
            fileWatcher = FileWatcher(url: fileURL) { [weak self] in
                DispatchQueue.main.async {
                    guard let self = self, !self.isWriting else { return }
                    self.reloadWorkItem?.cancel()
                    let workItem = DispatchWorkItem { [weak self] in
                        self?.load()
                    }
                    self.reloadWorkItem = workItem
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: workItem)
                }
            }
        }
    }

    func load() {
        guard let raw = try? Data(contentsOf: fileURL),
              let yaml = String(data: raw, encoding: .utf8) else {
            return
        }
        do {
            data = try YAMLDecoder().decode(T.self, from: yaml)
        } catch {
            print("\(label) load error: \(error)")
        }
    }

    func save() {
        isWriting = true
        do {
            let yaml = try YAMLEncoder().encode(data)
            try yaml.write(to: fileURL, atomically: true, encoding: .utf8)
        } catch {
            print("\(label) save error: \(error)")
            isWriting = false
            return
        }
        // Reset after a delay long enough to absorb the FileWatcher event from our own save
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.isWriting = false
        }
    }

    func update(_ block: (inout T) -> Void) {
        block(&data)
        save()
    }
}
