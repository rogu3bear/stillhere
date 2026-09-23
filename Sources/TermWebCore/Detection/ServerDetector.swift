/// The UI's single dependency for discovering and probing servers. Swappable with
/// `FakeServerDetector` for tests and previews.
public protocol ServerDetector: Sendable {
    /// All listeners, sorted by port, each classified as visible or hidden.
    func scan(config: IgnoreConfiguration) async throws -> [ServerEntry]
    func probe(_ entry: ServerEntry) async -> ProbeResult
}
