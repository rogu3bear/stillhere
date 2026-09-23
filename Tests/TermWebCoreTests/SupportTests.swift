import Foundation
import Testing
@testable import TermWebCore

@Suite struct UptimeFormatterTests {
    @Test(arguments: [
        (0.0, "0s"), (42.9, "42s"), (60, "1m"), (12 * 60 + 59, "12m"), (3_600, "1h"),
        (3 * 3_600 + 5 * 60, "3h 5m"), (86_400, "1d"), (2 * 86_400 + 4 * 3_600 + 59, "2d 4h"), (-5, "0s"),
    ] as [(TimeInterval, String)])
    func formats(_ interval: TimeInterval, _ expected: String) {
        #expect(UptimeFormatter.string(from: interval) == expected)
    }

    @Test func nonFiniteIsZero() {
        #expect(UptimeFormatter.string(from: .infinity) == "0s")
        #expect(UptimeFormatter.string(from: .nan) == "0s")
    }
}

@Suite struct SubprocessTests {
    @Test func capturesStdoutAndStatus() async throws {
        let output = try await Subprocess().run("/bin/echo", ["hello", "world"], timeout: .seconds(5))
        #expect(output.status == 0)
        #expect(output.text == "hello world\n")
    }

    @Test func reportsNonZeroExit() async throws {
        let output = try await Subprocess().run("/bin/sh", ["-c", "exit 3"], timeout: .seconds(5))
        #expect(output.status == 3)
        #expect(output.stdout.isEmpty)
    }

    @Test func drainsLargeOutputWithoutDeadlock() async throws {
        // 1 MB is far larger than a pipe buffer.
        let output = try await Subprocess().run("/bin/sh", ["-c", "head -c 1048576 /dev/zero"], timeout: .seconds(5))
        #expect(output.stdout.count == 1_048_576)
    }

    @Test func timesOut() async {
        let clock = ContinuousClock()
        let start = clock.now
        await #expect(throws: SubprocessError.timedOut(executable: "/bin/sleep")) {
            try await Subprocess().run("/bin/sleep", ["10"], timeout: .milliseconds(200))
        }
        #expect(clock.now - start < .seconds(3))
    }

    @Test func cancellationTerminatesTheProcess() async {
        let task = Task { try await Subprocess().run("/bin/sleep", ["10"], timeout: .seconds(20)) }
        try? await Task.sleep(for: .milliseconds(100))
        task.cancel()
        let result = await task.result
        #expect(throws: SubprocessError.cancelled(executable: "/bin/sleep")) { try result.get() }
    }

    @Test func missingExecutableFailsToLaunch() async {
        await #expect(throws: SubprocessError.self) {
            try await Subprocess().run("/nonexistent/tool", [], timeout: .seconds(1))
        }
    }
}

@Suite struct LibprocProcessInspectorTests {
    @Test func inspectsThisProcess() async throws {
        let pid = getpid()
        let details = await LibprocProcessInspector().details(for: [pid, pid, 999_999])
        #expect(details.keys.sorted() == [pid])
        let me = try #require(details[pid])
        #expect(me.ppid == getppid())
        #expect(me.uid == getuid())
        #expect(me.cwd == FileManager.default.currentDirectoryPath)
        #expect(!me.argv.isEmpty)
        #expect(me.executablePath?.hasPrefix("/") == true)
        #expect(!me.startTimeIsApproximate)
        #expect(try #require(me.startTime) < Date())
    }
}
