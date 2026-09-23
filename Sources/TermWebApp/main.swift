// Placeholder entry point until the menu bar app lands (STEP 2).
// Doubles as a live smoke test: `swift run term-web` prints what the detector sees.
import Foundation
import TermWebCore

let detector = DefaultServerDetector()
let showAll = CommandLine.arguments.contains("--all")
do {
    let entries = try await detector.scan(config: showAll ? .none : .defaults)
    for entry in entries {
        let hidden = entry.hiddenReason.map { " [hidden: \($0.label)]" } ?? ""
        let project = entry.project?.fullPath ?? "-"
        let uptime = entry.uptime(at: Date()).map(UptimeFormatter.string(from:)) ?? "-"
        print(":\(entry.port) \(entry.processName) (\(entry.rootPID)) \(entry.framework.name) \(uptime) \(project)\(hidden)")
        if entry.hiddenReason == nil {
            let probe = await detector.probe(entry)
            print("    \(probe.host) status=\(probe.status.map(String.init) ?? "-") title=\(probe.title ?? "-")")
        }
    }
} catch {
    print("scan failed: \(error)")
}
