import Foundation

// MARK: - Config (~/.config/fusen/config.yaml)

struct FusenConfig: Codable {
    var notes: [NoteConfig] = []
}

struct NoteConfig: Codable {
    var id: String?
    var path: String
    var title: String?
    var color: String?
    var transparency: Double?
    var fontSize: Int?
    var hotkey: String?

    enum CodingKeys: String, CodingKey {
        case id, path, title, color, transparency, hotkey
        case fontSize = "font_size"
    }
}

// MARK: - State (~/.local/state/fusen/state.yaml)

struct FusenState: Codable {
    var windows: [String: WindowState] = [:]
    var bookmarks: [String: String] = [:]  // noteId -> Base64 bookmark data
}

struct WindowState: Codable {
    var position: [Double]
    var size: [Double]
    var visible: Bool
    var alwaysOnTop: Bool?

    enum CodingKeys: String, CodingKey {
        case position, size, visible
        case alwaysOnTop = "always_on_top"
    }

    init(position: CGPoint, size: CGSize, visible: Bool, alwaysOnTop: Bool? = nil) {
        self.position = [position.x, position.y]
        self.size = [size.width, size.height]
        self.visible = visible
        self.alwaysOnTop = alwaysOnTop
    }

    var cgPoint: CGPoint { CGPoint(x: position[0], y: position[1]) }
    var cgSize: CGSize { CGSize(width: size[0], height: size[1]) }
}
