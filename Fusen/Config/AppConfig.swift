import Foundation

class AppConfig: YAMLStore<FusenConfig> {
    static let shared = AppConfig()

    var config: FusenConfig { data }

    private init() {
        let configDir = FileManager.realHomeDirectory
            .appendingPathComponent(".config/fusen")
        super.init(directory: configDir, fileName: "config.yaml", label: "Config", defaultValue: FusenConfig(), watchForChanges: true)
    }
}
