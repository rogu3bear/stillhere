import Testing
@testable import StillHereCore

@Suite struct ListenerGrouperTests {
    @Test func mergesIPv4AndIPv6SocketsOfOneProcess() throws {
        let groups = ListenerGrouper.group(LsofListenParser.parse(try Fixture.text("lsof-listen-machine.txt")))
        let airplay = try #require(groups.first { $0.port == 5000 })
        #expect(airplay.rootPID == 650)
        #expect(airplay.workerPIDs.isEmpty)
        #expect(airplay.bindings == [Binding(family: .ipv4, address: .any), Binding(family: .ipv6, address: .any)])
        #expect(groups.map(\.port) == groups.map(\.port).sorted())
        #expect(Set(groups.map(\.port)).count == groups.count)
    }

    @Test func forkedWorkersShareOneEntryWithParentAsRoot() throws {
        let groups = ListenerGrouper.group(LsofListenParser.parse(try Fixture.text("lsof-listen-dev.txt")))
        let forked = try #require(groups.first { $0.port == 8769 })
        #expect(forked.rootPID == 70_020)
        #expect(forked.workerPIDs == [70_021])
        #expect(forked.bindings == [Binding(family: .ipv4, address: .loopbackV4)])
        #expect(forked.memberPIDs == [70_020, 70_021])
    }

    @Test func dualStackSocketIsOneEntry() throws {
        let groups = ListenerGrouper.group(LsofListenParser.parse(try Fixture.text("lsof-listen-dev.txt")))
        let dual = try #require(groups.first { $0.port == 8767 })
        #expect(dual.bindings == [Binding(family: .ipv6, address: .any)])
        #expect(ProbeHosts.hosts(for: dual.bindings) == ["127.0.0.1", "[::1]"])
        #expect(groups.map(\.port) == [5000, 5173, 5432, 8765, 8767, 8769])
    }

    @Test func unrelatedProcessesOnOnePortAreSeparateEntries() {
        let records = [
            ListenerRecord(pid: 20, ppid: 1, command: "b", family: .ipv6, bindAddress: "::1", port: 9000),
            ListenerRecord(pid: 10, ppid: nil, command: "a", family: .ipv4, bindAddress: "127.0.0.1", port: 9000),
        ]
        let groups = ListenerGrouper.group(records)
        #expect(groups.map(\.rootPID) == [10, 20])
        #expect(groups.map(\.rootCommand) == ["a", "b"])
        #expect(groups.allSatisfy { $0.workerPIDs.isEmpty && $0.bindings.count == 1 })
    }

    @Test func siblingsFromOneShellAreNotMerged() {
        // Two servers started from the same terminal share a parent that is not listening.
        let records = [
            ListenerRecord(pid: 301, ppid: 300, command: "python3", family: .ipv4, bindAddress: "127.0.0.1", port: 8123),
            ListenerRecord(pid: 302, ppid: 300, command: "node", family: .ipv6, bindAddress: "::1", port: 8123),
        ]
        #expect(ListenerGrouper.group(records).map(\.memberPIDs) == [[301], [302]])
    }

    @Test func processTreeMergesAcrossGenerations() {
        let records = [
            ListenerRecord(pid: 100, ppid: 1, command: "gunicorn", family: .ipv4, bindAddress: "*", port: 8000),
            ListenerRecord(pid: 101, ppid: 100, command: "gunicorn", family: .ipv4, bindAddress: "*", port: 8000),
            ListenerRecord(pid: 102, ppid: 101, command: "gunicorn", family: .ipv4, bindAddress: "*", port: 8000),
            ListenerRecord(pid: 900, ppid: 1, command: "other", family: .ipv6, bindAddress: "::1", port: 8000),
        ]
        let groups = ListenerGrouper.group(records)
        #expect(groups.map(\.memberPIDs) == [[100, 101, 102], [900]])
    }

    @Test func entryIDsAreUniqueForSharedPorts() {
        let a = ServerEntry(port: 9000, rootPID: 10, bindings: [], command: "a", framework: FrameworkGuess(name: "a", source: .runtime))
        let b = ServerEntry(port: 9000, rootPID: 20, bindings: [], command: "b", framework: FrameworkGuess(name: "b", source: .runtime))
        #expect(a.id != b.id)
        #expect(a.id == a.probeKey.entryID)
    }

    @Test func probeHostsFollowBindings() {
        #expect(ProbeHosts.hosts(for: [Binding(family: .ipv6, address: .loopbackV6)]) == ["[::1]"])
        #expect(ProbeHosts.hosts(for: [Binding(family: .ipv4, address: .loopbackV4)]) == ["127.0.0.1"])
        #expect(ProbeHosts.hosts(for: [Binding(family: .ipv4, address: .any)]) == ["127.0.0.1"])
        #expect(ProbeHosts.hosts(for: [Binding(family: .ipv4, address: .other("192.168.1.5"))]) == ["127.0.0.1"])
        #expect(ProbeHosts.hosts(for: [
            Binding(family: .ipv4, address: .loopbackV4), Binding(family: .ipv6, address: .loopbackV6),
        ]) == ["127.0.0.1", "[::1]"])
    }
}
