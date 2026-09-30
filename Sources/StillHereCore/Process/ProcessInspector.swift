/// Looks up details for a batch of processes. PIDs that vanished or belong to
/// another user are omitted silently.
public protocol ProcessInspector: Sendable {
    func details(for pids: [Int32]) async -> [Int32: ProcessDetails]
}
