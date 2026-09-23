import Testing
@testable import TermWebCore

@Suite struct LsofListenParserTests {
    @Test func parsesRecordedMachineOutput() throws {
        let records = LsofListenParser.parse(try Fixture.text("lsof-listen-machine.txt"))
        let controlCenter = records.filter { $0.command == "ControlCenter" }
        #expect(controlCenter.count == 4)
        #expect(Set(controlCenter.map(\.port)) == [5000, 7000])
        #expect(Set(controlCenter.map(\.family)) == [.ipv4, .ipv6])
        #expect(controlCenter.allSatisfy { $0.pid == 650 && $0.ppid == 1 && $0.bindAddress == "*" })

        let bun = try #require(records.first { $0.command == "bun" })
        #expect(bun == ListenerRecord(pid: 21_749, ppid: 21_726, command: "bun", family: .ipv4, bindAddress: "127.0.0.1", port: 4173))
        #expect(records.contains { $0.command == "founder" && $0.port == 3100 })
        #expect(records.contains { $0.command == "star-mlxd" && $0.port == 8702 })
        #expect(records.contains { $0.command == "rapportd" && $0.port == 59_427 && $0.family == .ipv6 })
    }

    @Test func parsesAddressForms() {
        let text = """
        p1
        R0
        ca
        f1
        tIPv6
        n[::1]:5173
        f2
        tIPv4
        n*:8080
        f3
        tIPv4
        n127.0.0.1:8765
        f4
        tIPv6
        n[fe80::1%lo0]:9999
        """
        let records = LsofListenParser.parse(text)
        #expect(records.map(\.bindAddress) == ["::1", "*", "127.0.0.1", "fe80::1%lo0"])
        #expect(records.map(\.port) == [5173, 8080, 8765, 9999])
        #expect(records.map(\.binding.address) == [.loopbackV6, .any, .loopbackV4, .other("fe80::1%lo0")])
    }

    @Test func emptyOutputGivesNoRecords() {
        #expect(LsofListenParser.parse("").isEmpty)
    }

    @Test func skipsMalformedLines() {
        let text = """
        pnot-a-pid
        cghost
        f1
        tIPv4
        n*:1111
        p42
        cgood
        f1
        tIPv4
        n*:notaport
        f2
        tIPv4
        n*:70000
        f3
        tIPv4
        n127.0.0.1:5000->127.0.0.1:6000
        f4
        tunix
        n/tmp/sock:1
        f5
        n*:4000
        f6
        tIPv4
        n[::1:3000
        f7
        tIPv4
        n:3000

        xweird
        f8
        tIPv4
        n*:4242
        """
        let records = LsofListenParser.parse(text)
        #expect(records == [ListenerRecord(pid: 42, ppid: nil, command: "good", family: .ipv4, bindAddress: "*", port: 4242)])
    }

    @Test func listenerSourceTreatsExitOneWithEmptyOutputAsNoListeners() async throws {
        let source = LsofListenerSource(runner: FakeRunner([LsofListenerSource.executable: CommandOutput(1, "")]))
        #expect(try await source.listeners().isEmpty)
    }

    @Test func listenerSourceParsesOutputAndPassesExpectedArguments() async throws {
        let runner = FakeRunner([LsofListenerSource.executable: CommandOutput(0, try Fixture.text("lsof-listen-dev.txt"))])
        let records = try await LsofListenerSource(runner: runner).listeners()
        #expect(records.count == 8)
        #expect(runner.recordedCalls == [["/usr/sbin/lsof", "-nP", "-iTCP", "-sTCP:LISTEN", "-F", "pcRtn"]])
    }

    @Test func listenerSourceThrowsOnUnexpectedStatus() async {
        let source = LsofListenerSource(runner: FakeRunner([LsofListenerSource.executable: CommandOutput(2, "")]))
        await #expect(throws: DetectionError.commandFailed(executable: "/usr/sbin/lsof", status: 2)) {
            try await source.listeners()
        }
    }
}
