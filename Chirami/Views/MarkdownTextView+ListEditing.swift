import AppKit

extension MarkdownTextView {
    // MARK: - List item detection

    // swiftlint:disable force_try
    static let unorderedListPattern = try! NSRegularExpression(
        pattern: #"^(\s*)([-*])\s(\[[ xX]\]\s)?(.*)$"#
    )
    static let orderedListPattern = try! NSRegularExpression(
        pattern: #"^(\s*)(\d+)\.\s(.*)$"#
    )
    // swiftlint:enable force_try

    func isListItem(_ line: String, range: NSRange) -> Bool {
        Self.unorderedListPattern.firstMatch(in: line, range: range) != nil
            || Self.orderedListPattern.firstMatch(in: line, range: range) != nil
    }

    // MARK: - Toggle task list

    // swiftlint:disable force_try
    private static let taskCheckedPattern = try! NSRegularExpression(pattern: #"^(\s*)([-*])\s\[[xX]\]\s(.*)$"#)
    private static let taskUncheckedPattern = try! NSRegularExpression(pattern: #"^(\s*)([-*])\s\[ \]\s(.*)$"#)
    private static let listItemPattern = try! NSRegularExpression(
        pattern: #"^(\s*)([-*])\s(.*)$"#
    )
    private static let plainLinePattern = try! NSRegularExpression(
        pattern: #"^(\s*)(.+)$"#
    )
    // swiftlint:enable force_try

    func toggleTaskList() {
        guard let cl = currentLine() else { return }
        let storage = cl.storage
        let cursorLocation = cl.cursorLocation
        let lineRange = cl.lineRange
        let trimmedLine = cl.trimmedLine
        let fullRange = cl.fullRange

        let replacement: String

        if let match = Self.taskCheckedPattern.firstMatch(in: trimmedLine, range: fullRange) {
            // `- [x] content` → `- [ ] content`
            let indent = (trimmedLine as NSString).substring(with: match.range(at: 1))
            let marker = (trimmedLine as NSString).substring(with: match.range(at: 2))
            let content = (trimmedLine as NSString).substring(with: match.range(at: 3))
            replacement = "\(indent)\(marker) [ ] \(content)"
        } else if let match = Self.taskUncheckedPattern.firstMatch(in: trimmedLine, range: fullRange) {
            // `- [ ] content` → `- [x] content`
            let indent = (trimmedLine as NSString).substring(with: match.range(at: 1))
            let marker = (trimmedLine as NSString).substring(with: match.range(at: 2))
            let content = (trimmedLine as NSString).substring(with: match.range(at: 3))
            replacement = "\(indent)\(marker) [x] \(content)"
        } else if let match = Self.listItemPattern.firstMatch(in: trimmedLine, range: fullRange) {
            // `- content` → `- [ ] content`
            let indent = (trimmedLine as NSString).substring(with: match.range(at: 1))
            let marker = (trimmedLine as NSString).substring(with: match.range(at: 2))
            let content = (trimmedLine as NSString).substring(with: match.range(at: 3))
            replacement = "\(indent)\(marker) [ ] \(content)"
        } else if let match = Self.plainLinePattern.firstMatch(in: trimmedLine, range: fullRange) {
            // `content` → `- [ ] content`
            let indent = (trimmedLine as NSString).substring(with: match.range(at: 1))
            let content = (trimmedLine as NSString).substring(with: match.range(at: 2))
            replacement = "\(indent)- [ ] \(content)"
        } else if trimmedLine.isEmpty {
            // Empty line → insert `- [ ] `
            replacement = "- [ ] "
        } else {
            return
        }

        let replaceRange = NSRange(location: lineRange.location, length: (trimmedLine as NSString).length)
        let lengthDiff = (replacement as NSString).length - (trimmedLine as NSString).length

        if shouldChangeText(in: replaceRange, replacementString: replacement) {
            storage.replaceCharacters(in: replaceRange, with: replacement)
            let newCursor = max(lineRange.location, min(cursorLocation + lengthDiff, lineRange.location + (replacement as NSString).length))
            setSelectedRange(NSRange(location: newCursor, length: 0))
            didChangeText()
        }
    }

    // MARK: - Tab indentation for list items

    private static let indentUnit = "\t"

    override func insertTab(_ sender: Any?) {
        let sel = selectedRange()
        if sel.length > 0 {
            indentSelectedLines()
            return
        }

        guard let cl = currentLine() else {
            super.insertTab(sender)
            return
        }

        guard isListItem(cl.trimmedLine, range: cl.fullRange) else {
            super.insertTab(sender)
            return
        }

        let insertRange = NSRange(location: cl.lineRange.location, length: 0)
        let indent = Self.indentUnit
        if shouldChangeText(in: insertRange, replacementString: indent) {
            cl.storage.replaceCharacters(in: insertRange, with: indent)
            let newCursor = cl.cursorLocation + (indent as NSString).length
            setSelectedRange(NSRange(location: newCursor, length: 0))
            didChangeText()
        }
    }

    override func insertBacktab(_ sender: Any?) {
        let sel = selectedRange()
        if sel.length > 0 {
            dedentSelectedLines()
            return
        }

        guard let cl = currentLine() else { return }
        guard isListItem(cl.trimmedLine, range: cl.fullRange) else { return }

        let indent = Self.indentUnit
        let indentLen = (indent as NSString).length
        let lineText = cl.nsString.substring(with: cl.lineRange)
        guard lineText.hasPrefix(indent) else { return }

        let removeRange = NSRange(location: cl.lineRange.location, length: indentLen)
        if shouldChangeText(in: removeRange, replacementString: "") {
            cl.storage.replaceCharacters(in: removeRange, with: "")
            let newCursor = max(cl.lineRange.location, cl.cursorLocation - indentLen)
            setSelectedRange(NSRange(location: newCursor, length: 0))
            didChangeText()
        }
    }

    private func indentSelectedLines() {
        guard let storage = textStorage else { return }
        let sel = selectedRange()
        let nsString = storage.string as NSString
        let indent = Self.indentUnit
        let linesRange = nsString.lineRange(for: sel)
        let linesText = nsString.substring(with: linesRange)

        let lines = linesText.components(separatedBy: "\n")
        var result: [String] = []
        for (i, line) in lines.enumerated() {
            // Skip the trailing empty element from split and empty lines
            if (i == lines.count - 1 && line.isEmpty) || line.isEmpty {
                result.append(line)
            } else {
                result.append(indent + line)
            }
        }
        let replacement = result.joined(separator: "\n")

        if shouldChangeText(in: linesRange, replacementString: replacement) {
            storage.replaceCharacters(in: linesRange, with: replacement)
            let newLen = (replacement as NSString).length
            let selLen = replacement.hasSuffix("\n") ? newLen - 1 : newLen
            setSelectedRange(NSRange(location: linesRange.location, length: selLen))
            didChangeText()
        }
    }

    private func dedentSelectedLines() {
        guard let storage = textStorage else { return }
        let sel = selectedRange()
        let nsString = storage.string as NSString
        let indent = Self.indentUnit
        let linesRange = nsString.lineRange(for: sel)
        let linesText = nsString.substring(with: linesRange)

        let lines = linesText.components(separatedBy: "\n")
        var result: [String] = []
        var didRemove = false
        for line in lines {
            if line.hasPrefix(indent) {
                result.append(String(line.dropFirst((indent as NSString).length)))
                didRemove = true
            } else {
                result.append(line)
            }
        }
        guard didRemove else { return }
        let replacement = result.joined(separator: "\n")

        if shouldChangeText(in: linesRange, replacementString: replacement) {
            storage.replaceCharacters(in: linesRange, with: replacement)
            let newLen = (replacement as NSString).length
            let selLen = replacement.hasSuffix("\n") ? newLen - 1 : newLen
            setSelectedRange(NSRange(location: linesRange.location, length: selLen))
            didChangeText()
        }
    }

    // MARK: - List auto-continuation

    override func insertNewline(_ sender: Any?) {
        guard let cl = currentLine() else {
            super.insertNewline(sender)
            return
        }
        let storage = cl.storage
        let cursorLocation = cl.cursorLocation
        let lineRange = cl.lineRange

        // If cursor is at the very beginning of the line, just insert a plain newline
        // to avoid duplicating the list marker prefix (e.g. "- [ ]")
        if cursorLocation == lineRange.location {
            super.insertNewline(sender)
            return
        }

        let trimmedLine = cl.trimmedLine
        let fullRange = cl.fullRange

        // Try unordered / task list
        if let match = Self.unorderedListPattern.firstMatch(in: trimmedLine, range: fullRange) {
            let indent = (trimmedLine as NSString).substring(with: match.range(at: 1))
            let marker = (trimmedLine as NSString).substring(with: match.range(at: 2))
            let hasCheckbox = match.range(at: 3).location != NSNotFound
            let content = (trimmedLine as NSString).substring(with: match.range(at: 4))

            if content.isEmpty {
                // Empty list item → remove marker, end list
                if shouldChangeText(in: lineRange, replacementString: "") {
                    storage.replaceCharacters(in: lineRange, with: "")
                    setSelectedRange(NSRange(location: lineRange.location, length: 0))
                    didChangeText()
                }
                return
            }

            let nextMarker: String
            if hasCheckbox {
                nextMarker = "\(indent)\(marker) [ ] "
            } else {
                nextMarker = "\(indent)\(marker) "
            }

            let insertText = "\n\(nextMarker)"
            let insertRange = NSRange(location: cursorLocation, length: 0)
            if shouldChangeText(in: insertRange, replacementString: insertText) {
                storage.replaceCharacters(in: insertRange, with: insertText)
                setSelectedRange(NSRange(location: cursorLocation + (insertText as NSString).length, length: 0))
                didChangeText()
            }
            return
        }

        // Try ordered list
        if let match = Self.orderedListPattern.firstMatch(in: trimmedLine, range: fullRange) {
            let indent = (trimmedLine as NSString).substring(with: match.range(at: 1))
            let numberStr = (trimmedLine as NSString).substring(with: match.range(at: 2))
            let content = (trimmedLine as NSString).substring(with: match.range(at: 3))

            if content.isEmpty {
                // Empty list item → remove marker, end list
                if shouldChangeText(in: lineRange, replacementString: "") {
                    storage.replaceCharacters(in: lineRange, with: "")
                    setSelectedRange(NSRange(location: lineRange.location, length: 0))
                    didChangeText()
                }
                return
            }

            let nextNumber = (Int(numberStr) ?? 0) + 1
            let nextMarker = "\(indent)\(nextNumber). "
            let insertText = "\n\(nextMarker)"
            let insertRange = NSRange(location: cursorLocation, length: 0)
            if shouldChangeText(in: insertRange, replacementString: insertText) {
                storage.replaceCharacters(in: insertRange, with: insertText)
                setSelectedRange(NSRange(location: cursorLocation + (insertText as NSString).length, length: 0))
                didChangeText()
            }
            return
        }

        // No list marker → default newline
        super.insertNewline(sender)
    }
}
