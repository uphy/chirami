import AppKit
import os

// MARK: - ColorSchemeCSSConverter

enum ColorSchemeCSSConverter {
    static func cssVariables(for colorScheme: NoteColorScheme, isDark: Bool) -> String {
        let def = ColorSchemeRegistry.shared.definition(for: colorScheme)
        let bg = isDark ? def.background.dark : def.background.light
        let text = isDark ? def.text.dark : def.text.light
        let link = isDark ? def.link.dark : def.link.light
        let code = isDark ? def.code.dark : def.code.light
        let codeBg = isDark ? "rgba(255, 255, 255, 0.08)" : "rgba(0, 0, 0, 0.07)"
        let selectionAlpha = isDark ? 0.3 : 0.15

        return """
        --chirami-bg: \(rgb(bg));
        --chirami-text: \(rgb(text));
        --chirami-link: \(rgb(link));
        --chirami-code: \(rgb(code));
        --chirami-code-bg: \(codeBg);
        --chirami-selection: \(rgba(text, alpha: selectionAlpha));
        color-scheme: \(isDark ? "dark" : "light");
        """
    }

    private static func clamp(_ v: CGFloat) -> CGFloat {
        max(0, min(1, v))
    }

    private static func rgb(_ c: (r: CGFloat, g: CGFloat, b: CGFloat)) -> String {
        let r = Int((clamp(c.r) * 255).rounded())
        let g = Int((clamp(c.g) * 255).rounded())
        let b = Int((clamp(c.b) * 255).rounded())
        return "rgb(\(r), \(g), \(b))"
    }

    private static func rgba(_ c: (r: CGFloat, g: CGFloat, b: CGFloat), alpha: Double) -> String {
        let r = Int((clamp(c.r) * 255).rounded())
        let g = Int((clamp(c.g) * 255).rounded())
        let b = Int((clamp(c.b) * 255).rounded())
        return "rgba(\(r), \(g), \(b), \(alpha))"
    }
}

// MARK: - FontCSSConverter

enum FontCSSConverter {
    private static let logger = Logger(subsystem: "io.github.uphy.Chirami", category: "FontCSSConverter")
    private static let fallback = #"-apple-system, BlinkMacSystemFont, "Helvetica Neue", sans-serif"#

    static func cssFontFamily(from name: String?) -> String {
        guard let name, !name.isEmpty else { return fallback }
        // macOS internal font names starting with "." cannot be used in CSS
        if name.hasPrefix(".") { return fallback }
        if NSFont(name: name, size: 14) == nil {
            logger.warning("font not found, falling back to system font: \(name, privacy: .public)")
            return fallback
        }
        return "\"\(name)\", \(fallback)"
    }
}
