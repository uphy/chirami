import Foundation
import Yams

// MARK: - YAML Decodable models

private struct ColorSchemeFile: Decodable {
    let colors: [String: ColorSchemeEntry]
}

private struct ColorSchemeEntry: Decodable {
    let dark: ColorSchemeAppearanceColors
    let light: ColorSchemeAppearanceColors
}

private struct ColorSchemeAppearanceColors: Decodable {
    let background: [CGFloat]
    let text: [CGFloat]
    let link: [CGFloat]
    let code: [CGFloat]
}

// MARK: - ColorSchemeRegistry

final class ColorSchemeRegistry {
    static let shared = ColorSchemeRegistry()

    private var definitions: [String: NoteColorSchemeDef]
    private var builtInDefinitions: [String: NoteColorSchemeDef] = [:]

    private static let builtInNames = [
        NoteColorScheme.yellow, NoteColorScheme.blue, NoteColorScheme.green,
        NoteColorScheme.pink, NoteColorScheme.purple, NoteColorScheme.gray
    ].map { $0.name }

    private init() {
        guard
            let url = Bundle.module.url(forResource: "color_schemes", withExtension: "yaml"),
            let yaml = try? String(contentsOf: url, encoding: .utf8),
            let file = try? YAMLDecoder().decode(ColorSchemeFile.self, from: yaml)
        else {
            fatalError("Failed to load color_schemes.yaml from bundle")
        }

        var defs: [String: NoteColorSchemeDef] = [:]
        for (key, entry) in file.colors {
            defs[key] = NoteColorSchemeDef(
                background: makeColorSet(entry.dark.background, entry.light.background),
                text: makeColorSet(entry.dark.text, entry.light.text),
                link: makeColorSet(entry.dark.link, entry.light.link),
                code: makeColorSet(entry.dark.code, entry.light.code)
            )
        }
        for name in Self.builtInNames {
            guard defs[name] != nil else {
                fatalError("Missing color scheme definition for '\(name)' in color_schemes.yaml")
            }
        }
        self.builtInDefinitions = defs
        self.definitions = defs
    }

    func definition(for colorScheme: NoteColorScheme) -> NoteColorSchemeDef {
        definitions[colorScheme.name] ?? definitions["yellow"]!
    }

    func loadUserColorSchemes(_ colorSchemes: [String: ColorSchemeConfig]) {
        definitions = builtInDefinitions
        for (name, config) in colorSchemes {
            definitions[name] = NoteColorSchemeDef(
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
        fatalError("Color scheme array must have at least 3 RGB components")
    }
    return ColorSet(dark: (dark[0], dark[1], dark[2]), light: (light[0], light[1], light[2]))
}
