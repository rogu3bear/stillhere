import Testing
@testable import TermWebCore

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

    @Test func unrelatedProcessesOnOnePortPickLowestPIDAsRoot() {
        let records = [
            ListenerRecord(pid: 20, ppid: 1, command: "b", family: .ipv6, bindAddress: "::1", port: 9000),
            ListenerRecord(pid: 10, ppid: nil, command: "a", family: .ipv4, bindAddress: "127.0.0.1", port: 9000),
        ]
        let group = ListenerGrouper.group(records)[0]
        #expect(group.rootPID == 10)
        #expect(group.rootCommand == "a")
        #expect(group.workerPIDs == [20])
        #expect(group.bindings.count == 2)
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
