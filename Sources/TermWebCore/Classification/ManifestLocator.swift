import Foundation

/// Finds the nearest directory at or above a process cwd that holds a manifest.
public enum ManifestLocator {
    /// Walks up from `cwd`. Stops (returning nil) at `home`, at `/`, or after checking a
    /// directory that contains `.git` (the repository root) without finding a manifest.
    public static func locate(
        from cwd: String,
        home: String,
        fileExists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }
    ) -> URL? {
        let homePath = URL(fileURLWithPath: home).standardizedFileURL.path
        var directory = URL(fileURLWithPath: cwd, isDirectory: true).standardizedFileURL
        while true {
            let path = directory.path
            if path == "/" || path == homePath { return nil }
            if ManifestKind.allCases.contains(where: { fileExists(directory.appending(path: $0.rawValue).path) }) {
                return directory
            }
            if fileExists(directory.appending(path: ".git").path) { return nil }
            directory = directory.deletingLastPathComponent()
        }
    }
}
