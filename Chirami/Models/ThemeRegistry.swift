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

    private var definitions: [String: NoteColorDef]
    private var builtInDefinitions: [String: NoteColorDef] = [:]

    private static let builtInNames = [
        NoteColor.yellow, NoteColor.blue, NoteColor.green,
        NoteColor.pink, NoteColor.purple, NoteColor.gray
    ].map { $0.name }

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
        for name in Self.builtInNames {
            guard defs[name] != nil else {
                fatalError("Missing theme definition for '\(name)' in themes.yaml")
            }
        }
        self.builtInDefinitions = defs
        self.definitions = defs
    }

    func definition(for color: NoteColor) -> NoteColorDef {
        definitions[color.name] ?? definitions["yellow"]!
    }

    func loadUserThemes(_ themes: [String: ThemeConfig]) {
        definitions = builtInDefinitions
        for (name, config) in themes {
            definitions[name] = NoteColorDef(
                background: makeColorSet(config.dark.background.map { CGFloat($0) }, config.light.background.map { CGFloat($0) }),
                text: makeColorSet(config.dark.text.map { CGFloat($0) }, config.light.text.map { CGFloat($0) }),
                link: makeColorSet(config.dark.link.map { CGFloat($0) }, config.light.link.map { CGFloat($0) }),
                code: makeColorSet(config.dark.code.map { CGFloat($0) }, config.light.code.map { CGFloat($0) })
            )
        }
    }
}

private func makeColorSet(_ dark: [CGFloat], _ light: [CGFloat]) -> ColorSet {
    guard dark.count >= 3, light.count >= 3 else {
        fatalError("Theme color array must have at least 3 RGB components")
    }
    return ColorSet(dark: (dark[0], dark[1], dark[2]), light: (light[0], light[1], light[2]))
}
