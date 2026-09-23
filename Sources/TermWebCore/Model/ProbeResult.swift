import Foundation

/// Outcome of one quick HTTP GET against a loopback listener.
public struct ProbeResult: Sendable, Hashable {
    public enum Failure: Sendable, Hashable {
        case refused
        case timedOut
        case other(Int)
    }

    public var host: String
    /// "http" or "https": the scheme that produced this result.
    public var scheme: String
    public var status: Int?
    public var title: String?
    public var location: String?
    public var serverHeader: String?
    public var poweredBy: String?
    public var latency: Duration
    public var failure: Failure?

    public init(
        host: String,
        scheme: String = "http",
        status: Int? = nil,
        title: String? = nil,
        location: String? = nil,
        serverHeader: String? = nil,
        poweredBy: String? = nil,
        latency: Duration = .zero,
        failure: Failure? = nil
    ) {
        self.host = host
        self.scheme = scheme
        self.status = status
        self.title = title
        self.location = location
        self.serverHeader = serverHeader
        self.poweredBy = poweredBy
        self.latency = latency
        self.failure = failure
    }
}
