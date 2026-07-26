import Foundation
import os

/// Resolves `[[wiki link]]` targets to local `.md` files and opens them with a
/// user-configured command. Path resolution is filesystem-only (it never runs
/// inside the WebView), so this is the Swift counterpart of the JS click bridge.
///
/// Resolution order mirrors Obsidian's defaults, simplified to file granularity:
///   1. A file next to the source note (same directory).
///   2. The shortest matching `.md` under the vault root.
/// The vault root comes from `wikilink.vault`, or is discovered by walking up
/// from the source note looking for an `.obsidian` directory.
enum WikiLinkResolver {
    private static let logger = Logger(subsystem: "io.github.uphy.Chirami", category: "WikiLinkResolver")

    /// Default command when `wikilink.open` is unset: open with the OS handler.
    private static let defaultCommand: CommandTemplate = .args(["open", "{{path}}"])

    /// Directory names skipped while scanning the vault.
    private static let ignoredDirectories: Set<String> = [".obsidian", ".git", ".trash", "node_modules"]

    /// Characters left unescaped when building `{{path_encoded}}`. Keeps path
    /// separators readable while escaping spaces/non-ASCII and the reserved
    /// characters that would break a URL query (`&`, `=`, `?`, `#`, `+`).
    private static let pathEncodingAllowed: CharacterSet = {
        var set = CharacterSet.urlPathAllowed
        set.remove(charactersIn: "&=?#+")
        return set
    }()

    /// - Parameter noteConfig: the per-note override (if any). Each field falls
    ///   back to the global `wikilink` config, then to the built-in default.
    @MainActor
    static func open(target rawTarget: String, sourceFileURL: URL?, noteConfig: WikiLinkConfig? = nil) {
        let global = AppConfig.shared.config.wikilink
        let command = noteConfig?.open ?? global?.open ?? defaultCommand
        let vaultOverride = noteConfig?.vault ?? global?.vault

        // Resolution touches the filesystem (potentially a large vault scan), so
        // run it off the main thread to keep the editor responsive.
        DispatchQueue.global(qos: .userInitiated).async {
            run(rawTarget: rawTarget, sourceFileURL: sourceFileURL, command: command, vaultOverride: vaultOverride)
        }
    }

    // MARK: - Resolution

    private static func run(rawTarget: String, sourceFileURL: URL?, command: CommandTemplate, vaultOverride: String?) {
        // `[[name#heading|alias]]` — only `name` matters for file resolution.
        let name = linkName(from: rawTarget)
        guard !name.isEmpty else {
            logger.warning("empty wiki link target: \(rawTarget, privacy: .public)")
            return
        }

        let sourceDir = sourceFileURL?.deletingLastPathComponent()
        let vaultRoot = resolveVaultRoot(override: vaultOverride, sourceDir: sourceDir)

        guard let resolved = resolvePath(name: name, sourceDir: sourceDir, vaultRoot: vaultRoot) else {
            logger.warning("wiki link not found: \(name, privacy: .public) (vault: \(vaultRoot?.path ?? "none", privacy: .public))")
            return
        }

        logger.info("wiki link resolved: \(name, privacy: .public) -> \(resolved.path, privacy: .public)")
        execute(command: command, path: resolved, vaultRoot: vaultRoot, name: name)
    }

    /// Strips the optional `#heading` and `|alias` from a wiki link target.
    private static func linkName(from raw: String) -> String {
        var name = raw.trimmingCharacters(in: .whitespaces)
        if let pipe = name.firstIndex(of: "|") {
            name = String(name[..<pipe])
        }
        if let hash = name.firstIndex(of: "#") {
            name = String(name[..<hash])
        }
        return name.trimmingCharacters(in: .whitespaces)
    }

    private static func resolveVaultRoot(override: String?, sourceDir: URL?) -> URL? {
        if let override, !override.trimmingCharacters(in: .whitespaces).isEmpty {
            let expanded = (override as NSString).expandingTildeInPath
            return URL(fileURLWithPath: expanded).standardizedFileURL
        }
        guard let sourceDir else { return nil }
        return findVaultRoot(from: sourceDir)
    }

    /// Walks up from `dir` looking for a directory containing `.obsidian`.
    private static func findVaultRoot(from dir: URL) -> URL? {
        var current = dir.standardizedFileURL
        let fm = FileManager.default
        while true {
            var isDir: ObjCBool = false
            let marker = current.appendingPathComponent(".obsidian").path
            if fm.fileExists(atPath: marker, isDirectory: &isDir), isDir.boolValue {
                return current
            }
            let parent = current.deletingLastPathComponent()
            if parent.path == current.path { return nil }
            current = parent
        }
    }

    private static func resolvePath(name: String, sourceDir: URL?, vaultRoot: URL?) -> URL? {
        let relative = name.hasSuffix(".md") ? name : name + ".md"
        let fm = FileManager.default

        // (a) Relative to the source note's directory.
        if let sourceDir {
            let candidate = sourceDir.appendingPathComponent(relative).standardizedFileURL
            if fm.fileExists(atPath: candidate.path) {
                return candidate
            }
        }

        // (b) Shortest match anywhere under the vault root.
        if let vaultRoot {
            return shortestMatch(relative: relative, in: vaultRoot)
        }
        return nil
    }

    /// Finds the `.md` file under `root` whose relative path best matches
    /// `relative`, preferring the shortest path (Obsidian's tie-breaker).
    private static func shortestMatch(relative: String, in root: URL) -> URL? {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return nil }

        let target = relative.lowercased()
        let targetLeaf = (target as NSString).lastPathComponent
        let hasSlash = relative.contains("/")
        let rootPath = root.standardizedFileURL.path

        var best: URL?
        var bestLength = Int.max

        for case let url as URL in enumerator {
            let values = try? url.resourceValues(forKeys: [.isDirectoryKey])
            if values?.isDirectory == true {
                if ignoredDirectories.contains(url.lastPathComponent) {
                    enumerator.skipDescendants()
                }
                continue
            }
            guard url.pathExtension.lowercased() == "md" else { continue }

            let standardized = url.standardizedFileURL.path
            // Relative path within the vault, lowercased for case-insensitive match.
            let rel = standardized.hasPrefix(rootPath + "/")
                ? String(standardized.dropFirst(rootPath.count + 1)).lowercased()
                : standardized.lowercased()

            let matches: Bool
            if hasSlash {
                // Subpath link: match the full relative path or a suffix segment.
                matches = rel == target || rel.hasSuffix("/" + target)
            } else {
                // Bare name link: match by file name only.
                matches = (rel as NSString).lastPathComponent == targetLeaf
            }
            guard matches else { continue }

            if rel.count < bestLength {
                bestLength = rel.count
                best = url.standardizedFileURL
            }
        }
        return best
    }

    // MARK: - Command execution

    private static func execute(command: CommandTemplate, path: URL, vaultRoot: URL?, name: String) {
        // Percent-encoded variant for embedding the path in a URL/URI such as
        // `obsidian://open?path={{path_encoded}}` (handles spaces & non-ASCII).
        let encodedPath = path.path.addingPercentEncoding(withAllowedCharacters: pathEncodingAllowed) ?? path.path
        let tokens: [String: String] = [
            "{{path}}": path.path,
            "{{path_encoded}}": encodedPath,
            "{{vault}}": vaultRoot?.path ?? "",
            "{{target}}": name
        ]
        let envVars: [String: String] = [
            "CHIRAMI_TARGET": path.path,
            "CHIRAMI_TARGET_ENCODED": encodedPath,
            "CHIRAMI_VAULT": vaultRoot?.path ?? "",
            "CHIRAMI_TARGET_NAME": name
        ]

        let process = Process()
        process.environment = augmentedEnvironment(with: envVars)

        switch command {
        case .args(let rawArgs):
            let args = rawArgs.map { substitute($0, tokens: tokens) }
            guard !args.isEmpty else {
                logger.warning("wikilink.open is an empty command array")
                return
            }
            // /usr/bin/env resolves the program against PATH and never invokes a
            // shell, so resolved file names are passed as literal arguments.
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = args
        case .shell(let rawCommand):
            let cmd = substitute(rawCommand, tokens: tokens)
            process.executableURL = URL(fileURLWithPath: "/bin/sh")
            process.arguments = ["-c", cmd]
        }

        do {
            try process.run()
        } catch {
            logger.error("failed to launch wikilink command: \(error.localizedDescription, privacy: .public)")
        }
    }

    private static func substitute(_ template: String, tokens: [String: String]) -> String {
        var result = template
        for (key, value) in tokens {
            result = result.replacingOccurrences(of: key, with: value)
        }
        return result
    }

    /// Inherits the app environment but augments PATH with the common locations
    /// where CLI launchers live, since a Finder-launched app gets a minimal PATH.
    private static func augmentedEnvironment(with extra: [String: String]) -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        let home = FileManager.realHomeDirectory.path
        let extraPaths = ["/opt/homebrew/bin", "/usr/local/bin", "\(home)/.local/bin", "/usr/bin", "/bin"]
        var paths = (env["PATH"] ?? "").split(separator: ":").map(String.init)
        for p in extraPaths where !paths.contains(p) {
            paths.append(p)
        }
        env["PATH"] = paths.joined(separator: ":")
        for (key, value) in extra {
            env[key] = value
        }
        return env
    }
}
