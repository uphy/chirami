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

    init(directory: URL, fileName: String, label: String, defaultValue: T) {
        self.fileURL = directory.appendingPathComponent(fileName)
        self.label = label
        self.data = defaultValue

        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        load()
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
        do {
            let yaml = try YAMLEncoder().encode(data)
            try yaml.write(to: fileURL, atomically: true, encoding: .utf8)
        } catch {
            print("\(label) save error: \(error)")
        }
    }

    func update(_ block: (inout T) -> Void) {
        block(&data)
        save()
    }
}
