import Foundation
import Yams

// MARK: - YAML Decodable models

private struct ThemeFile: Decodable {
    let colors: [String: ThemeColorEntry]
}

private struct ThemeColorEntry: Decodable {
    let dark: ThemeAppearanceColors
    let light: ThemeAppearanceColors
}

private struct ThemeAppearanceColors: Decodable {
    let background: [CGFloat]
    let text: [CGFloat]
    let link: [CGFloat]
    let code: [CGFloat]
}

// MARK: - ThemeRegistry

final class ThemeRegistry {
    static let shared = ThemeRegistry()

    private let definitions: [String: NoteColorDef]

    private init() {
        guard
            let url = Bundle.module.url(forResource: "themes", withExtension: "yaml"),
            let yaml = try? String(contentsOf: url, encoding: .utf8),
            let file = try? YAMLDecoder().decode(ThemeFile.self, from: yaml)
        else {
            fatalError("Failed to load themes.yaml from bundle")
        }

        var defs: [String: NoteColorDef] = [:]
        for (key, entry) in file.colors {
            defs[key] = NoteColorDef(
                background: makeColorSet(entry.dark.background, entry.light.background),
                text: makeColorSet(entry.dark.text, entry.light.text),
                link: makeColorSet(entry.dark.link, entry.light.link),
                code: makeColorSet(entry.dark.code, entry.light.code)
            )
        }
        self.definitions = defs

        for color in NoteColor.allCases {
            guard definitions[color.rawValue] != nil else {
                fatalError("Missing theme definition for '\(color.rawValue)' in themes.yaml")
            }
        }
    }

    func definition(for color: NoteColor) -> NoteColorDef {
        definitions[color.rawValue]!
    }
}

private func makeColorSet(_ dark: [CGFloat], _ light: [CGFloat]) -> ColorSet {
    guard dark.count >= 3, light.count >= 3 else {
        fatalError("Theme color array must have at least 3 RGB components")
    }
    return ColorSet(dark: (dark[0], dark[1], dark[2]), light: (light[0], light[1], light[2]))
}
