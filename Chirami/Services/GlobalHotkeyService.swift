import Foundation
import HotKey
import AppKit
import os

class GlobalHotkeyService {
    private let logger = Logger(subsystem: "com.uphy.Chirami", category: "GlobalHotkeyService")
    private var hotKeys: [String: HotKey] = [:]

    func register(id: String, keyString: String, onToggle: @escaping () -> Void) {
        // Remove existing registration for this id
        hotKeys.removeValue(forKey: id)

        let (key, modifiers) = parseKeyString(keyString)
        guard let key = key else {
            logger.warning("could not parse hotkey '\(keyString, privacy: .public)'")
            return
        }

        let hotKey = HotKey(key: key, modifiers: modifiers)
        hotKey.keyDownHandler = onToggle
        hotKeys[id] = hotKey
    }

    func unregisterAll() {
        hotKeys.removeAll()
    }

    // MARK: - Key string parsing

    private func parseKeyString(_ string: String) -> (Key?, NSEvent.ModifierFlags) {
        let parts = string.lowercased().components(separatedBy: "+")
        var modifiers: NSEvent.ModifierFlags = []
        var keyChar = ""

        for part in parts {
            switch part {
            case "cmd", "command": modifiers.insert(.command)
            case "shift":         modifiers.insert(.shift)
            case "opt", "option": modifiers.insert(.option)
            case "ctrl", "control": modifiers.insert(.control)
            default:              keyChar = part
            }
        }

        return (keyMap[keyChar], modifiers)
    }

    private let keyMap: [String: Key] = [
        "a": .a, "b": .b, "c": .c, "d": .d, "e": .e,
        "f": .f, "g": .g, "h": .h, "i": .i, "j": .j,
        "k": .k, "l": .l, "m": .m, "n": .n, "o": .o,
        "p": .p, "q": .q, "r": .r, "s": .s, "t": .t,
        "u": .u, "v": .v, "w": .w, "x": .x, "y": .y, "z": .z,
        "0": .zero, "1": .one, "2": .two, "3": .three, "4": .four,
        "5": .five, "6": .six, "7": .seven, "8": .eight, "9": .nine,
        "return": .return, "space": .space, "delete": .delete,
        "escape": .escape, "tab": .tab,
        "f1": .f1, "f2": .f2, "f3": .f3, "f4": .f4, "f5": .f5,
        "f6": .f6, "f7": .f7, "f8": .f8, "f9": .f9, "f10": .f10
    ]
}
