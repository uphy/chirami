#!/usr/bin/env swift
// Send a key sequence to the focused Chirami note, refusing to type anywhere else.
//
// Before every step Chirami must be frontmost with a focused panel; otherwise
// the script aborts (exit 1) so keys never leak into the terminal.
//
// Usage:
//   swift chirami_keys.swift <step> [<step> ...]
// Steps:
//   tab, shift+tab, ctrl+a, cmd+shift+z, option+left ...   key chord
//   text:Hello world                                        type text (unicode, no IME)
//   sleep:300                                               wait N ms
//   html:<b>x</b>|x                                         set clipboard to HTML (+ plain after |)
//   clip:plain text                                         set clipboard to plain text (\n and \t escapes)
//
// Synthesized events bypass Karabiner-Elements, so send the keys *after* Karabiner's
// translation (e.g. down instead of ctrl+n).

import AppKit
import ApplicationServices

let bundleID = "io.github.uphy.Chirami"

let keyCodes: [String: CGKeyCode] = [
    "a": 0, "s": 1, "d": 2, "f": 3, "h": 4, "g": 5, "z": 6, "x": 7, "c": 8, "v": 9,
    "b": 11, "q": 12, "w": 13, "e": 14, "r": 15, "y": 16, "t": 17, "1": 18, "2": 19,
    "3": 20, "4": 21, "6": 22, "5": 23, "=": 24, "9": 25, "7": 26, "-": 27, "8": 28,
    "0": 29, "]": 30, "o": 31, "u": 32, "[": 33, "i": 34, "p": 35, "return": 36, "enter": 36,
    "l": 37, "j": 38, "'": 39, "k": 40, ";": 41, "\\": 42, ",": 43, "/": 44, "n": 45,
    "m": 46, ".": 47, "tab": 48, "space": 49, "`": 50, "backspace": 51, "delete": 51,
    "escape": 53, "forwarddelete": 117, "home": 115, "end": 119, "pageup": 116,
    "pagedown": 121, "left": 123, "right": 124, "down": 125, "up": 126
]

func fail(_ message: String) -> Never {
    FileHandle.standardError.write((message + "\n").data(using: .utf8)!)
    exit(1)
}

guard let chirami = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first else {
    fail("Chirami is not running")
}

// Keys reach Chirami only when it is the active app *and* one of its panels is
// focused. (The system-wide AXFocusedUIElement query fails with -25204 here.)
func focusIsChirami() -> Bool {
    guard NSWorkspace.shared.frontmostApplication?.processIdentifier == chirami.processIdentifier else {
        return false
    }
    let app = AXUIElementCreateApplication(chirami.processIdentifier)
    var value: AnyObject?
    return AXUIElementCopyAttributeValue(app, kAXFocusedWindowAttribute as CFString, &value) == .success
        && value != nil
}

func post(_ code: CGKeyCode, _ flags: CGEventFlags) {
    let src = CGEventSource(stateID: .hidSystemState)
    for down in [true, false] {
        let e = CGEvent(keyboardEventSource: src, virtualKey: code, keyDown: down)!
        e.flags = flags
        e.post(tap: .cghidEventTap)
        usleep(8_000)
    }
}

let shiftedChars: [Character: Character] = [
    "!": "1", "@": "2", "#": "3", "$": "4", "%": "5", "^": "6", "&": "7", "*": "8", "(": "9", ")": "0",
    "_": "-", "+": "=", "{": "[", "}": "]", "|": "\\", ":": ";", "\"": "'", "<": ",", ">": ".", "?": "/", "~": "`"
]

func typeText(_ text: String) {
    let src = CGEventSource(stateID: .hidSystemState)
    for ch in text {
        if ch == "\n" { post(36, []); continue }
        if ch == "\t" { post(48, []); continue }
        if ch == " " { post(49, []); continue }
        // ASCII goes through real key codes (US layout): unicode-string injection
        // is dropped by WebKit right after a ctrl chord.
        if let code = keyCodes[String(ch)] { post(code, []); continue }
        if ch.isASCII, ch.isUppercase, let code = keyCodes[ch.lowercased()] { post(code, .maskShift); continue }
        if let base = shiftedChars[ch], let code = keyCodes[String(base)] { post(code, .maskShift); continue }
        let units = Array(String(ch).utf16)
        for down in [true, false] {
            let e = CGEvent(keyboardEventSource: src, virtualKey: 0, keyDown: down)!
            e.keyboardSetUnicodeString(stringLength: units.count, unicodeString: units)
            e.post(tap: .cghidEventTap)
            usleep(6_000)
        }
    }
}

func unescape(_ s: String) -> String {
    s.replacingOccurrences(of: "\\n", with: "\n").replacingOccurrences(of: "\\t", with: "\t")
}

for step in CommandLine.arguments.dropFirst() {
    if step.hasPrefix("sleep:") {
        usleep(useconds_t((Int(step.dropFirst(6)) ?? 0) * 1000))
        continue
    }
    if step.hasPrefix("clip:") {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(unescape(String(step.dropFirst(5))), forType: .string)
        continue
    }
    if step.hasPrefix("html:") {
        let body = String(step.dropFirst(5))
        let parts = body.split(separator: "|", maxSplits: 1).map(String.init)
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(unescape(parts[0]), forType: .html)
        pb.setString(unescape(parts.count > 1 ? parts[1] : parts[0]), forType: .string)
        continue
    }
    guard focusIsChirami() else { fail("focus is not on Chirami; aborted before step '\(step)'") }
    if step.hasPrefix("text:") {
        typeText(unescape(String(step.dropFirst(5))))
        usleep(30_000)
        continue
    }
    var flags: CGEventFlags = []
    var parts = step.lowercased().split(separator: "+").map(String.init)
    // "+" itself is not supported as a key; use shift+= instead.
    let keyName = parts.removeLast()
    for m in parts {
        switch m {
        case "cmd", "command": flags.insert(.maskCommand)
        case "ctrl", "control": flags.insert(.maskControl)
        case "opt", "option", "alt": flags.insert(.maskAlternate)
        case "shift": flags.insert(.maskShift)
        default: fail("unknown modifier: \(m)")
        }
    }
    guard let code = keyCodes[keyName] else { fail("unknown key: \(keyName)") }
    post(code, flags)
    usleep(40_000)
}
