import Foundation
import Darwin
import Yams

extension FileManager {
    static var realHomeDirectory: URL {
        if let pw = getpwuid(getuid()) {
            return URL(fileURLWithPath: String(cString: pw.pointee.pw_dir))
        }
        return FileManager.default.homeDirectoryForCurrentUser
    }
}

class AppConfig: ObservableObject {
    static let shared = AppConfig()

    private let configURL: URL
    @Published private(set) var config: FusenConfig = FusenConfig()

    private init() {
        let configDir = FileManager.realHomeDirectory
            .appendingPathComponent(".config/fusen")
        configURL = configDir.appendingPathComponent("config.yaml")

        try? FileManager.default.createDirectory(at: configDir, withIntermediateDirectories: true)
        load()
    }

    func load() {
        guard let data = try? Data(contentsOf: configURL),
              let yaml = String(data: data, encoding: .utf8) else {
            config = FusenConfig()
            return
        }
        do {
            config = try YAMLDecoder().decode(FusenConfig.self, from: yaml)
        } catch {
            print("Config load error: \(error)")
            config = FusenConfig()
        }
    }

    func save() {
        do {
            let yaml = try YAMLEncoder().encode(config)
            try yaml.write(to: configURL, atomically: true, encoding: .utf8)
        } catch {
            print("Config save error: \(error)")
        }
    }

    func update(_ block: (inout FusenConfig) -> Void) {
        block(&config)
        save()
    }
}
