import Foundation

/// Loopback-only prober: ephemeral session, no proxy, no cookies or cache, redirects
/// reported instead of followed, at most 64 KB read.
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
        session = URLSession(configuration: configuration, delegate: NoRedirects(), delegateQueue: nil)
    }

    deinit { session.invalidateAndCancel() }

    public func probe(port: Int, bindings: [Binding]) async -> ProbeResult {
        let hosts = ProbeHosts.hosts(for: bindings)
        var result = await probe(host: hosts[0], port: port)
        // A second host is tried only when the first refused the connection.
        if result.failure == .refused, hosts.count > 1 {
            result = await probe(host: hosts[1], port: port)
        }
        return result
    }

    func probe(host: String, port: Int) async -> ProbeResult {
        guard let url = URL(string: "http://\(host):\(port)/") else {
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
                status: http?.statusCode,
                title: TitleExtractor.title(from: body),
                location: http?.value(forHTTPHeaderField: "Location"),
                serverHeader: http?.value(forHTTPHeaderField: "Server"),
                poweredBy: http?.value(forHTTPHeaderField: "X-Powered-By"),
                latency: clock.now - start
            )
        } catch {
            return ProbeResult(host: host, latency: clock.now - start, failure: Self.failure(for: error))
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

/// Reports 30x responses as-is so a probe never leaves loopback.
private final class NoRedirects: NSObject, URLSessionTaskDelegate, Sendable {
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest
    ) async -> URLRequest? {
        nil
    }
}
