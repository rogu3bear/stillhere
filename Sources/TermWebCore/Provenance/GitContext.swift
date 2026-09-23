import Foundation

/// The git checkout a server runs from.
public struct GitContext: Sendable, Hashable, Codable {
    /// Directory holding `.git` (the checkout root; a linked worktree's own root).
    public var checkoutRoot: String
    /// Branch name, nil when HEAD is detached.
    public var branch: String?
    /// Abbreviated commit when HEAD is detached.
    public var detachedCommit: String?
    /// Linked worktree name (`.git/worktrees/<name>`), nil for the main checkout.
    public var worktree: String?

    public init(checkoutRoot: String, branch: String? = nil, detachedCommit: String? = nil, worktree: String? = nil) {
        self.checkoutRoot = checkoutRoot
        self.branch = branch
        self.detachedCommit = detachedCommit
        self.worktree = worktree
    }

    /// "main", "feat/x", or "detached 1a2b3c4".
    public var headDescription: String {
        if let branch { return branch }
        if let detachedCommit { return "detached \(detachedCommit)" }
        return "unknown HEAD"
    }
}

/// Reads branch and worktree from `.git` files directly: no `git` subprocess, no locks.
public enum GitReader {
    /// Walks up from `directory` to the nearest `.git`, stopping at `home` and `/`.
    public static func context(
        for directory: String,
        home: String,
        read: (String) -> String? = { try? String(contentsOfFile: $0, encoding: .utf8) },
        isDirectory: (String) -> Bool? = GitReader.isDirectory
    ) -> GitContext? {
        let homePath = URL(fileURLWithPath: home, isDirectory: true).standardized.path
        var current = URL(fileURLWithPath: directory, isDirectory: true).standardized
        while true {
            let path = current.path
            let dotGit = current.appending(path: ".git").path
            switch isDirectory(dotGit) {
            case true?:
                return context(checkoutRoot: path, gitDirectory: dotGit, worktree: nil, read: read)
            case false?:
                guard let pointer = read(dotGit).flatMap(parseGitdirPointer) else { return nil }
                let gitDirectory = pointer.hasPrefix("/")
                    ? pointer
                    : current.appending(path: pointer).standardized.path
                let worktree = gitDirectory.contains("/worktrees/")
                    ? URL(fileURLWithPath: gitDirectory).lastPathComponent
                    : nil
                return context(checkoutRoot: path, gitDirectory: gitDirectory, worktree: worktree, read: read)
            case nil:
                break
            }
            if path == "/" || path == homePath { return nil }
            current = current.deletingLastPathComponent()
        }
    }

    static func context(checkoutRoot: String, gitDirectory: String, worktree: String?, read: (String) -> String?) -> GitContext? {
        guard let head = read(gitDirectory + "/HEAD") else { return nil }
        let parsed = parseHead(head)
        return GitContext(checkoutRoot: checkoutRoot, branch: parsed.branch, detachedCommit: parsed.commit, worktree: worktree)
    }

    /// `ref: refs/heads/feat/x` -> branch `feat/x`; a bare hash -> detached commit.
    static func parseHead(_ contents: String) -> (branch: String?, commit: String?) {
        let line = contents.trimmingCharacters(in: .whitespacesAndNewlines)
        if line.hasPrefix("ref: ") {
            let ref = String(line.dropFirst(5))
            let prefix = "refs/heads/"
            return (ref.hasPrefix(prefix) ? String(ref.dropFirst(prefix.count)) : ref, nil)
        }
        let isHash = line.count >= 7 && line.allSatisfy(\.isHexDigit)
        return (nil, isHash ? String(line.prefix(7)) : nil)
    }

    /// A linked worktree's `.git` file: `gitdir: /repo/.git/worktrees/name`.
    static func parseGitdirPointer(_ contents: String) -> String? {
        let line = contents.trimmingCharacters(in: .whitespacesAndNewlines)
        guard line.hasPrefix("gitdir: ") else { return nil }
        let path = String(line.dropFirst(8))
        return path.isEmpty ? nil : path
    }

    /// true for a directory, false for a file, nil when nothing exists at `path`.
    public static func isDirectory(_ path: String) -> Bool? {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) else { return nil }
        return isDirectory.boolValue
    }
}
