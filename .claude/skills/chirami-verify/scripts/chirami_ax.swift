#!/usr/bin/env swift
// Read and operate Chirami note windows through the macOS Accessibility API.
//
// Note panels are .floating-level NSPanels (kCGWindowLayer 3) exposed as
// AXWindow/AXSystemDialog, which generic tools such as agent-desktop skip.
// This script talks to the Chirami process directly instead.
//
// Usage:
//   swift chirami_ax.swift dump    [--title Test]            # print the AX tree of the note
//   swift chirami_ax.swift text    [--title Test]            # print the rendered editor text
//   swift chirami_ax.swift visible [--title Test]            # exit 0 if shown, 1 if hidden
//   swift chirami_ax.swift press <role> <label> [--nth N] [--title Test]
//       e.g. press AXCheckBox "task one" / press AXButton close
//
// Exit codes: 0 ok, 1 note window not found, 2 usage error, 3 element not found, 4 AX error.

import AppKit
import ApplicationServices

let bundleID = "io.github.uphy.Chirami"

func fail(_ message: String, _ code: Int32) -> Never {
    FileHandle.standardError.write((message + "\n").data(using: .utf8)!)
    exit(code)
}

func attr(_ e: AXUIElement, _ name: String) -> AnyObject? {
    var value: AnyObject?
    return AXUIElementCopyAttributeValue(e, name as CFString, &value) == .success ? value : nil
}

func str(_ e: AXUIElement, _ name: String) -> String {
    guard let v = attr(e, name) else { return "" }
    if let s = v as? String { return s }
    if let n = v as? NSNumber { return n.stringValue }
    return ""
}

func children(_ e: AXUIElement) -> [AXUIElement] {
    attr(e, "AXChildren") as? [AXUIElement] ?? []
}

func actions(_ e: AXUIElement) -> [String] {
    var names: CFArray?
    AXUIElementCopyActionNames(e, &names)
    return (names as? [String] ?? []).filter { !$0.hasPrefix("AXScroll") && $0 != "AXShowMenu" }
}

// MARK: - Arguments

var args = Array(CommandLine.arguments.dropFirst())
func takeOption(_ name: String) -> String? {
    guard let i = args.firstIndex(of: name), i + 1 < args.count else { return nil }
    let v = args[i + 1]
    args.removeSubrange(i...(i + 1))
    return v
}
let title = takeOption("--title") ?? "Test"
let nth = Int(takeOption("--nth") ?? "1") ?? 1
guard let command = args.first else { fail("usage: chirami_ax.swift dump|text|visible|press ...", 2) }

// MARK: - Locate the note window

guard AXIsProcessTrusted() else { fail("Accessibility permission is not granted to the launching app", 4) }
guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first else {
    fail("Chirami is not running", 1)
}
let appElement = AXUIElementCreateApplication(app.processIdentifier)
// Hidden (ordered-out) panels are not listed in AXWindows, so presence == visible.
let window = (attr(appElement, "AXWindows") as? [AXUIElement] ?? []).first { str($0, "AXTitle") == title }

if command == "visible" {
    print(window == nil ? "hidden" : "visible")
    exit(window == nil ? 1 : 0)
}
guard let window else { fail("note window '\(title)' is not shown", 1) }

// MARK: - Labels

// A node's human-readable label. CodeMirror task checkboxes carry no title,
// so they take the text of the following AXStaticText sibling.
func label(_ e: AXUIElement, siblings: [AXUIElement], index: Int) -> String {
    for name in ["AXTitle", "AXDescription"] {
        let s = str(e, name)
        if !s.isEmpty { return s }
    }
    let role = str(e, "AXRole")
    if role == "AXCheckBox" || role == "AXRadioButton" {
        if index + 1 < siblings.count, str(siblings[index + 1], "AXRole") == "AXStaticText" {
            return str(siblings[index + 1], "AXValue")
        }
        return ""
    }
    if str(e, "AXSubrole") == "AXCloseButton" { return "close" }
    return role == "AXTextArea" ? "" : str(e, "AXValue")
}

// MARK: - Commands

func dump(_ e: AXUIElement, depth: Int, siblings: [AXUIElement], index: Int) {
    let role = str(e, "AXRole")
    let sub = str(e, "AXSubrole")
    let value = str(e, "AXValue").replacingOccurrences(of: "\n", with: "\\n")
    let lbl = label(e, siblings: siblings, index: index)
    let acts = actions(e)
    // Skip anonymous wrapper groups to keep the output readable.
    if !(role == "AXGroup" && lbl.isEmpty && value.isEmpty) {
        var line = String(repeating: "  ", count: depth) + role
        if !sub.isEmpty { line += "(\(sub))" }
        if !lbl.isEmpty, lbl != value { line += " label=\"\(lbl)\"" }
        if !value.isEmpty { line += " value=\"\(value.prefix(120))\"" }
        if !acts.isEmpty { line += " [\(acts.joined(separator: ","))]" }
        print(line)
    }
    let kids = children(e)
    for (i, c) in kids.enumerated() { dump(c, depth: depth + 1, siblings: kids, index: i) }
}

func findAll(_ e: AXUIElement, role: String, label wanted: String, into result: inout [AXUIElement]) {
    let kids = children(e)
    for (i, c) in kids.enumerated() {
        if str(c, "AXRole") == role && label(c, siblings: kids, index: i) == wanted { result.append(c) }
        findAll(c, role: role, label: wanted, into: &result)
    }
}

func firstDescendant(_ e: AXUIElement, role: String) -> AXUIElement? {
    for c in children(e) {
        if str(c, "AXRole") == role { return c }
        if let found = firstDescendant(c, role: role) { return found }
    }
    return nil
}

switch command {
case "dump":
    dump(window, depth: 0, siblings: [window], index: 0)
case "text":
    guard let area = firstDescendant(window, role: "AXTextArea") else { fail("editor text area not found", 3) }
    print(str(area, "AXValue"), terminator: "")
case "press":
    guard args.count >= 3 else { fail("usage: press <role> <label> [--nth N]", 2) }
    var matches: [AXUIElement] = []
    findAll(window, role: args[1], label: args[2], into: &matches)
    guard nth >= 1, nth <= matches.count else {
        fail("no \(args[1]) labelled \"\(args[2])\" (found \(matches.count), wanted #\(nth))", 3)
    }
    let result = AXUIElementPerformAction(matches[nth - 1], "AXPress" as CFString)
    guard result == .success else { fail("AXPress failed: \(result.rawValue)", 4) }
    print("pressed")
default:
    fail("unknown command: \(command)", 2)
}
