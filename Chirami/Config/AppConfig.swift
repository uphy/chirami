import Foundation

class AppConfig: YAMLStore<ChiramiConfig> {
    static let shared = AppConfig()

    var config: ChiramiConfig { data }

    private init() {
        let configDir = FileManager.realHomeDirectory
            .appendingPathComponent(".config/chirami")
        super.init(directory: configDir, fileName: "config.yaml", label: "Config", defaultValue: ChiramiConfig(), watchForChanges: true)
    }
}
