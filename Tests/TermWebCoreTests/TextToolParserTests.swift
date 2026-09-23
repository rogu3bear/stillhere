import Foundation
import Testing
@testable import TermWebCore

@Suite struct LsofCwdParserTests {
    @Test func parsesBatchedCwdOutput() throws {
        let cwds = LsofCwdParser.parse(try Fixture.text("lsof-cwd.txt"))
        #expect(cwds == [70_001: "/Users/dev/Projects/shop", 70_030: "/Users/dev/Downloads/site", 70_050: "/"])
    }
}

@Suite struct PsParserTests {
    @Test func parsesRowsAndSkipsGarbage() throws {
        let rows = PsParser.parse(try Fixture.text("ps.txt"))
        #expect(rows.map(\.pid) == [70_001, 70_030, 70_050])
        #expect(rows[0].elapsed == 12 * 60 + 34)
        #expect(rows[1].elapsed == 3_723)
        #expect(rows[2].elapsed == ((3 * 24 + 4) * 60 + 5) * 60 + 6)
        #expect(rows[1].command == "/opt/homebrew/bin/python3 -m http.server 8765 --bind 127.0.0.1")
        #expect(rows[2].ppid == 1)
    }

    @Test func elapsedFormats() {
        #expect(PsParser.parseElapsed("00:05") == 5)
        #expect(PsParser.parseElapsed("1-00:00:00") == 86_400)
        #expect(PsParser.parseElapsed("61:00") == nil)
        #expect(PsParser.parseElapsed("5") == nil)
        #expect(PsParser.parseElapsed("x-01:00") == nil)
    }

    @Test func lsofInspectorCombinesBothBatches() async throws {
        let runner = FakeRunner([
            "/usr/sbin/lsof": CommandOutput(1, try Fixture.text("lsof-cwd.txt")),
            "/bin/ps": CommandOutput(1, try Fixture.text("ps.txt")),
        ])
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let inspector = LsofProcessInspector(runner: runner, clock: FixedNow(now))
        let details = await inspector.details(for: [70_030, 70_001, 70_001, 70_050])

        let vite = try #require(details[70_001])
        #expect(vite.cwd == "/Users/dev/Projects/shop")
        #expect(vite.argv == ["/usr/local/bin/node", "/Users/dev/Projects/shop/node_modules/.bin/vite"])
        #expect(vite.name == "node")
        #expect(vite.startTime == now.addingTimeInterval(-754))
        #expect(vite.startTimeIsApproximate)
        #expect(details[70_050]?.cwd == "/")
        #expect(Set(runner.recordedCalls) == [
            ["/usr/sbin/lsof", "-a", "-p", "70001,70030,70050", "-d", "cwd", "-Fn"],
            ["/bin/ps", "-ww", "-o", "pid=,ppid=,etime=,command=", "-p", "70001,70030,70050"],
        ])
    }
}
