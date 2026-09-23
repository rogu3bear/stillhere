import Foundation
import Testing
@testable import TermWebCore

@Suite struct HTTPSchemeTests {
    @Test(arguments: [
        NSURLErrorNetworkConnectionLost,
        NSURLErrorCannotParseResponse,
        NSURLErrorBadServerResponse,
    ])
    func nonHTTPAnswersSuggestTLS(code: Int) {
        #expect(URLSessionHTTPProber.suggestsTLS(ProbeResult(host: "127.0.0.1", failure: .other(code))))
    }

    @Test func refusalsTimeoutsAndSuccessDoNotSuggestTLS() {
        #expect(!URLSessionHTTPProber.suggestsTLS(ProbeResult(host: "127.0.0.1", failure: .refused)))
        #expect(!URLSessionHTTPProber.suggestsTLS(ProbeResult(host: "127.0.0.1", failure: .timedOut)))
        #expect(!URLSessionHTTPProber.suggestsTLS(ProbeResult(host: "127.0.0.1", status: 200)))
    }

    @Test func urlFollowsTheProbedScheme() {
        let entry = ServerEntry(port: 5173, rootPID: 10, bindings: [], command: "node", framework: FrameworkGuess(name: "Node", source: .runtime))
        #expect(entry.url(for: nil).absoluteString == "http://localhost:5173/")
        #expect(entry.url(for: ProbeResult(host: "127.0.0.1", status: 200)).absoluteString == "http://localhost:5173/")
        let secure = ProbeResult(host: "127.0.0.1", scheme: "https", status: 200)
        #expect(entry.url(for: secure).absoluteString == "https://localhost:5173/")
    }
}
