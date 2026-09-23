/// Quick HTTP GET against a loopback listener.
public protocol HTTPProber: Sendable {
    func probe(port: Int, bindings: [Binding]) async -> ProbeResult
}
