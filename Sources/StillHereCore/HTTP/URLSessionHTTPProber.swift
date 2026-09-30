import Foundation

/// Loopback-only prober: ephemeral session, no proxy, no cookies or cache, redirects
/// reported instead of followed, at most 64 KB read. Falls back to HTTPS (accepting
/// self-signed certificates, which is safe only because every request is loopback) when
/// plain HTTP gets a non-HTTP answer, as TLS-only dev servers give.
public final class URLSessionHTTPProber: HTTPProber {
    private let session: URLSession

    public init(requestTimeout: TimeInterval = 1.5, resourceTimeout: TimeInterval = 2) {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = requestTimeout
        configuration.timeoutIntervalForResource = resourceTimeout
        configuration.connectionProxyDictionary = [:]
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        session = URLSession(configuration: configuration, delegate: LoopbackDelegate(), delegateQueue: nil)
    }

    deinit { session.invalidateAndCancel() }

    public func probe(port: Int, bindings: [Binding]) async -> ProbeResult {
        let hosts = ProbeHosts.hosts(for: bindings)
        var result = await probe(host: hosts[0], port: port)
        // A second host is tried only when the first refused the connection.
        if result.failure == .refused, hosts.count > 1 {
            result = await probe(host: hosts[1], port: port)
        }
        if Self.suggestsTLS(result) {
            let secure = await probe(host: result.host, port: port, scheme: "https")
            if secure.failure == nil { result = secure }
        }
        return result
    }

    /// Plain HTTP sent to a TLS listener is dropped or answered with garbage; refusals and
    /// timeouts say nothing about TLS.
    static func suggestsTLS(_ result: ProbeResult) -> Bool {
        guard case .other(let code) = result.failure else { return false }
        return [
            NSURLErrorNetworkConnectionLost,
            NSURLErrorCannotParseResponse,
            NSURLErrorBadServerResponse,
        ].contains(code)
    }

    func probe(host: String, port: Int, scheme: String = "http") async -> ProbeResult {
        guard let url = URL(string: "\(scheme)://\(host):\(port)/") else {
            return ProbeResult(host: host, failure: .other(NSURLErrorBadURL))
        }
        var request = URLRequest(url: url)
        request.setValue("text/html", forHTTPHeaderField: "Accept")
        let clock = ContinuousClock()
        let start = clock.now
        do {
            let (bytes, response) = try await session.bytes(for: request)
            defer { bytes.task.cancel() }
            var body = Data()
            body.reserveCapacity(TitleExtractor.maxBytes)
            for try await byte in bytes {
                body.append(byte)
                if body.count >= TitleExtractor.maxBytes { break }
            }
            let http = response as? HTTPURLResponse
            return ProbeResult(
                host: host,
                scheme: scheme,
                status: http?.statusCode,
                title: TitleExtractor.title(from: body),
                location: http?.value(forHTTPHeaderField: "Location"),
                serverHeader: http?.value(forHTTPHeaderField: "Server"),
                poweredBy: http?.value(forHTTPHeaderField: "X-Powered-By"),
                latency: clock.now - start
            )
        } catch {
            return ProbeResult(host: host, scheme: scheme, latency: clock.now - start, failure: Self.failure(for: error))
        }
    }

    static func failure(for error: any Error) -> ProbeResult.Failure {
        let code = (error as? URLError)?.code.rawValue ?? (error as NSError).code
        switch code {
        case NSURLErrorCannotConnectToHost: return .refused
        case NSURLErrorTimedOut: return .timedOut
        default: return .other(code)
        }
    }
}

/// Reports 30x responses as-is so a probe never leaves loopback, and trusts the
/// self-signed certificates dev servers use, for loopback hosts only.
private final class LoopbackDelegate: NSObject, URLSessionTaskDelegate, Sendable {
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest
    ) async -> URLRequest? {
        nil
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didReceive challenge: URLAuthenticationChallenge
    ) async -> (URLSession.AuthChallengeDisposition, URLCredential?) {
        let space = challenge.protectionSpace
        guard space.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              Self.loopbackHosts.contains(space.host),
              let trust = space.serverTrust
        else { return (.performDefaultHandling, nil) }
        return (.useCredential, URLCredential(trust: trust))
    }

    private static let loopbackHosts: Set<String> = ["127.0.0.1", "::1", "[::1]", "localhost"]
}
