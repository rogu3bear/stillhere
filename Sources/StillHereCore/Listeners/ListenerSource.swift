/// Produces the current set of TCP listening sockets visible to this user.
public protocol ListenerSource: Sendable {
    func listeners() async throws -> [ListenerRecord]
}

public enum DetectionError: Error, Sendable, Equatable {
    case commandFailed(executable: String, status: Int32)
}
