import Foundation
import TermWebCore

/// A probe result tied to the exact process it was taken from.
struct ProbeRecord: Hashable {
    var key: ServerEntry.ProbeKey
    var result: ProbeResult
    var probedAt: Date
}

/// Bounded HTTP probing of visible entries. Each probe runs on the detector (off the
/// main actor); results are delivered one by one as they finish, so fast servers show
/// their title without waiting for slow ones.
struct ProbeScheduler {
    static let maxConcurrent = 4

    private(set) var inFlight: Set<ServerEntry.ProbeKey> = []

    /// Entries whose cached probe is missing, belongs to a different process, or is older
    /// than `maxAge`. Hidden entries and entries already being probed are skipped.
    func entriesNeedingProbe(
        _ entries: [ServerEntry],
        records: [ServerEntry.ID: ProbeRecord],
        now: Date,
        maxAge: TimeInterval
    ) -> [ServerEntry] {
        entries.filter { entry in
            guard !entry.isHidden, !inFlight.contains(entry.probeKey) else { return false }
            guard let record = records[entry.id], record.key == entry.probeKey else { return true }
            return now.timeIntervalSince(record.probedAt) >= maxAge
        }
    }

    mutating func begin(_ entries: [ServerEntry]) {
        inFlight.formUnion(entries.map(\.probeKey))
    }

    mutating func end(_ key: ServerEntry.ProbeKey) {
        inFlight.remove(key)
    }

    /// Probes `entries` with at most `maxConcurrent` requests in flight and calls
    /// `deliver` on the caller's actor for each completed probe. Stops starting and
    /// delivering probes once the calling task is cancelled (the panel closed). The caller
    /// clears the in-flight marks it set with `begin`.
    static func probe(
        _ entries: [ServerEntry],
        using detector: any ServerDetector,
        maxConcurrent: Int = maxConcurrent,
        deliver: (ServerEntry.ProbeKey, ProbeResult) -> Void
    ) async {
        await withTaskGroup(of: (ServerEntry.ProbeKey, ProbeResult).self) { group in
            var pending = entries.makeIterator()
            func enqueueNext() {
                guard let entry = pending.next() else { return }
                group.addTask { (entry.probeKey, await detector.probe(entry)) }
            }
            for _ in 0..<max(1, maxConcurrent) { enqueueNext() }
            while let (key, result) = await group.next() {
                // A cancelled URLSession request reports an error, not the server's state.
                guard !Task.isCancelled else { continue }
                deliver(key, result)
                enqueueNext()
            }
        }
    }
}
