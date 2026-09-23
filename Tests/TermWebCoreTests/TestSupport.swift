import Foundation
import Synchronization
import Testing
@testable import TermWebCore

enum Fixture {
    static func url(_ name: String) throws -> URL {
        let url = Bundle.module.url(forResource: name, withExtension: nil, subdirectory: "Fixtures")
        return try #require(url, "missing fixture \(name)")
    }

    static func text(_ name: String) throws -> String {
        try String(contentsOf: url(name), encoding: .utf8)
    }

    static func data(_ name: String) throws -> Data {
        try Data(contentsOf: url(name))
    }
}

/// Canned command output keyed by executable path; records every call.
final class FakeRunner: CommandRunner {
    private let outputs: [String: CommandOutput]
    private let calls = Mutex<[[String]]>([])

    init(_ outputs: [String: CommandOutput]) { self.outputs = outputs }

    var recordedCalls: [[String]] { calls.withLock { $0 } }

    func run(_ executable: String, _ arguments: [String], timeout: Duration) async throws -> CommandOutput {
        calls.withLock { $0.append([executable] + arguments) }
        guard let output = outputs[executable] else {
            throw SubprocessError.launchFailed(executable: executable, message: "not faked")
        }
        return output
    }
}

extension CommandOutput {
    init(_ status: Int32, _ text: String) {
        self.init(status: status, stdout: Data(text.utf8))
    }
}

/// A fresh temporary directory, removed by the caller.
func makeTemporaryDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appending(path: "term-web-tests-\(UUID().uuidString)", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url.resolvingSymlinksInPath()
}
