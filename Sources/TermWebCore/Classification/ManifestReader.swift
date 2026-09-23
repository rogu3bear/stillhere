import Foundation

/// Reads project manifests (at most 256 KB each) and caches the facts per directory
/// until any manifest's modification date changes.
public actor ManifestReader {
    static let maxBytes = 256 * 1024

    private struct CacheEntry {
        var signature: [ManifestKind: Date]
        var facts: ManifestFacts
    }

    private var cache: [String: CacheEntry] = [:]
    public private(set) var readCount = 0

    public init() {}

    public func facts(in directory: URL) -> ManifestFacts {
        let signature = Self.signature(of: directory)
        if let cached = cache[directory.path], cached.signature == signature { return cached.facts }
        readCount += 1
        let facts = Self.read(directory: directory, kinds: Set(signature.keys))
        cache[directory.path] = CacheEntry(signature: signature, facts: facts)
        return facts
    }

    private static func signature(of directory: URL) -> [ManifestKind: Date] {
        var result: [ManifestKind: Date] = [:]
        for kind in ManifestKind.allCases {
            let path = directory.appending(path: kind.rawValue).path
            guard let attributes = try? FileManager.default.attributesOfItem(atPath: path) else { continue }
            result[kind] = attributes[.modificationDate] as? Date ?? .distantPast
        }
        return result
    }

    static func read(directory: URL, kinds: Set<ManifestKind>) -> ManifestFacts {
        var facts = ManifestFacts(directory: directory, kinds: kinds)
        for kind in kinds {
            guard let data = readPrefix(directory.appending(path: kind.rawValue)) else { continue }
            switch kind {
            case .packageJSON:
                let package = parsePackageJSON(data)
                facts.dependencies.formUnion(package.dependencies)
                facts.devScript = package.devScript
            case .gemfile:
                facts.dependencies.formUnion(parseGemfile(String(decoding: data, as: UTF8.self)))
            case .pyproject, .requirements:
                facts.dependencies.formUnion(pythonTokens(String(decoding: data, as: UTF8.self)))
            case .managePy, .cargo, .goMod, .denoJSON, .denoJSONC:
                continue
            }
        }
        return facts
    }

    private static func readPrefix(_ url: URL) -> Data? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        return try? handle.read(upToCount: maxBytes)
    }

    static func parsePackageJSON(_ data: Data) -> (dependencies: Set<String>, devScript: String?) {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return ([], nil) }
        var names = Set<String>()
        for key in ["dependencies", "devDependencies"] {
            if let table = object[key] as? [String: Any] { names.formUnion(table.keys.map { $0.lowercased() }) }
        }
        let devScript = (object["scripts"] as? [String: Any])?["dev"] as? String
        return (names, devScript)
    }

    /// Gem names from `gem "name"` / `gem 'name'` lines.
    static func parseGemfile(_ text: String) -> Set<String> {
        var names = Set<String>()
        for line in text.split(whereSeparator: \.isNewline) {
            let trimmed = line.drop { $0 == " " || $0 == "\t" }
            guard trimmed.hasPrefix("gem ") || trimmed.hasPrefix("gem\t") else { continue }
            let rest = trimmed.dropFirst(4).drop { $0 == " " || $0 == "\t" }
            guard let quote = rest.first, quote == "\"" || quote == "'" else { continue }
            let name = rest.dropFirst().prefix { $0 != quote }
            if !name.isEmpty { names.insert(name.lowercased()) }
        }
        return names
    }

    /// Lowercased identifier-like tokens; enough to test for `django`, `flask`, `fastapi`.
    static func pythonTokens(_ text: String) -> Set<String> {
        let separators = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_")).inverted
        return Set(text.lowercased().components(separatedBy: separators).filter { !$0.isEmpty })
    }
}
