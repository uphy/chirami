import Foundation

enum PeriodicFileNavigator {
    /// テンプレートにマッチするファイル一覧をソート済みで返す
    static func listMatchingFiles(template: String, baseDirectory: URL) -> [URL] {
        let fm = FileManager.default
        let resolvedBase = baseDirectory.resolvingSymlinksInPath()
        guard let enumerator = fm.enumerator(
            at: resolvedBase,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        let baseComponents = resolvedBase.pathComponents
        var matchedFiles: [(relativePath: String, url: URL)] = []

        while let url = enumerator.nextObject() as? URL {
            guard let resourceValues = try? url.resourceValues(forKeys: [.isRegularFileKey]),
                  resourceValues.isRegularFile == true
            else { continue }

            let resolved = url.resolvingSymlinksInPath()
            let fileComponents = resolved.pathComponents
            guard fileComponents.count > baseComponents.count else { continue }
            let relativePath = Array(fileComponents.dropFirst(baseComponents.count)).joined(separator: "/")

            if PathTemplateResolver.matches(relativePath: relativePath, template: template) {
                matchedFiles.append((relativePath, resolved))
            }
        }

        // 相対パスの lexicographic ソート
        matchedFiles.sort { $0.relativePath < $1.relativePath }
        return matchedFiles.map(\.url)
    }

    /// ソート済みファイルリスト内で current の前のファイルを返す
    static func previousFile(from current: URL, in sortedFiles: [URL]) -> URL? {
        guard let index = sortedFiles.firstIndex(where: { $0.path == current.path }),
              index > 0
        else { return nil }
        return sortedFiles[index - 1]
    }

    /// ソート済みファイルリスト内で current の次のファイルを返す
    static func nextFile(from current: URL, in sortedFiles: [URL]) -> URL? {
        guard let index = sortedFiles.firstIndex(where: { $0.path == current.path }),
              index < sortedFiles.count - 1
        else { return nil }
        return sortedFiles[index + 1]
    }
}
