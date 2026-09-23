import Foundation

/// The folder a server was started from, and the project it belongs to.
public struct ProjectLocation: Sendable, Hashable {
    /// The process working directory.
    public var cwd: URL
    /// The nearest directory containing a manifest, or `cwd` when none was found.
    public var projectRoot: URL

    public init(cwd: URL, projectRoot: URL) {
        self.cwd = cwd
        self.projectRoot = projectRoot
    }

    /// Folder name shown in the row.
    public var displayName: String { projectRoot.lastPathComponent }

    /// Full path shown on hover.
    public var fullPath: String {
        let path = projectRoot.path(percentEncoded: false)
        return path.count > 1 && path.hasSuffix("/") ? String(path.dropLast()) : path
    }
}
