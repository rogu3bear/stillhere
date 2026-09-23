import Foundation

/// Deterministic fixtures for previews and tests.
public enum SampleServers {
    /// Fixed reference time; sample start times are relative to it.
    public static let referenceDate = Date(timeIntervalSince1970: 1_790_000_000)

    public static let vite = entry(
        port: 5173, pid: 41_001, name: "node", bindings: [Binding(family: .ipv6, address: .loopbackV6)],
        argv: ["/usr/local/bin/node", "/Users/dev/Projects/shop/node_modules/.bin/vite"],
        project: "/Users/dev/Projects/shop", framework: FrameworkGuess(name: "Vite", source: .argv), age: 754
    )
    public static let next = entry(
        port: 3000, pid: 41_020, name: "node", bindings: [Binding(family: .ipv6, address: .any)],
        argv: ["next-server (v15.0.0)"],
        project: "/Users/dev/Projects/blog", framework: FrameworkGuess(name: "Next.js", source: .argv), age: 3_900
    )
    public static let flask = entry(
        port: 5000, pid: 41_100, name: "Python", bindings: [Binding(family: .ipv4, address: .any)],
        argv: ["/opt/homebrew/bin/python3", "-m", "flask", "run"],
        project: "/Users/dev/Projects/api", framework: FrameworkGuess(name: "Flask", source: .argv), age: 95
    )
    public static let rails = entry(
        port: 3001, pid: 41_200, name: "ruby", bindings: [Binding(family: .ipv4, address: .loopbackV4)],
        argv: ["ruby", "bin/rails", "server", "-p", "3001"],
        project: "/Users/dev/Projects/store", framework: FrameworkGuess(name: "Rails", source: .argv), age: 200_000
    )
    public static let httpServer = entry(
        port: 8000, pid: 41_300, name: "Python", bindings: [Binding(family: .ipv4, address: .loopbackV4)],
        argv: ["/opt/homebrew/opt/python@3.13/Frameworks/Python.framework/Versions/3.13/Resources/Python.app/Contents/MacOS/Python", "-m", "http.server"],
        project: "/Users/dev/Downloads/site", framework: FrameworkGuess(name: "Python http.server", source: .argv), age: 12
    )
    public static let uvicorn = entry(
        port: 8001, pid: 41_400, workers: [41_401], name: "Python", bindings: [Binding(family: .ipv4, address: .loopbackV4)],
        argv: ["/Users/dev/Projects/ml/.venv/bin/python", "-m", "uvicorn", "app:app", "--reload", "--port", "8001"],
        project: "/Users/dev/Projects/ml", framework: FrameworkGuess(name: "FastAPI", source: .argv), age: 1_800
    )
    public static let controlCenter = entry(
        port: 7000, pid: 650, name: "ControlCenter",
        bindings: [Binding(family: .ipv4, address: .any), Binding(family: .ipv6, address: .any)],
        argv: ["/System/Library/CoreServices/ControlCenter.app/Contents/MacOS/ControlCenter"],
        project: nil, framework: FrameworkGuess(name: "ControlCenter", source: .runtime), age: 90_000, hidden: .system
    )
    public static let postgres = entry(
        port: 5432, pid: 900, name: "postgres", bindings: [Binding(family: .ipv4, address: .loopbackV4)],
        argv: ["/opt/homebrew/opt/postgresql@17/bin/postgres", "-D", "/opt/homebrew/var/postgresql@17"],
        project: nil, framework: FrameworkGuess(name: "postgres", source: .runtime), age: 90_000,
        hidden: .ignoredName("postgres")
    )

    /// Sorted by port, like a real scan.
    public static let all: [ServerEntry] = [next, rails, flask, postgres, vite, controlCenter, httpServer, uvicorn]
        .sorted { $0.port < $1.port }

    public static let probes: [Int: ProbeResult] = [
        5173: ProbeResult(host: ProbeHosts.ipv6, status: 200, title: "Shop — Vite + React", latency: .milliseconds(3)),
        3000: ProbeResult(host: ProbeHosts.ipv4, status: 200, title: "My Blog", poweredBy: "Next.js", latency: .milliseconds(40)),
        5000: ProbeResult(host: ProbeHosts.ipv4, status: 404, serverHeader: "Werkzeug/3.0.1 Python/3.13.0", latency: .milliseconds(2)),
        3001: ProbeResult(host: ProbeHosts.ipv4, status: 302, location: "/users/sign_in", serverHeader: "Puma", latency: .milliseconds(12)),
        8000: ProbeResult(host: ProbeHosts.ipv4, status: 200, title: "Directory listing for /", serverHeader: "SimpleHTTP/0.6 Python/3.13.0", latency: .milliseconds(1)),
        8001: ProbeResult(host: ProbeHosts.ipv4, failure: .timedOut),
    ]

    static func entry(
        port: Int, pid: Int32, workers: [Int32] = [], name: String, bindings: [Binding], argv: [String],
        project: String?, framework: FrameworkGuess, age: TimeInterval, hidden: HiddenReason? = nil
    ) -> ServerEntry {
        let process = ProcessDetails(
            pid: pid, ppid: 1, uid: 501, name: name,
            startTime: referenceDate.addingTimeInterval(-age),
            executablePath: argv.first.flatMap { $0.hasPrefix("/") ? $0 : nil },
            argv: argv, cwd: project ?? "/"
        )
        let location = project.map { path in
            let url = URL(fileURLWithPath: path, isDirectory: true)
            return ProjectLocation(cwd: url, projectRoot: url)
        }
        return ServerEntry(
            port: port, rootPID: pid, workerPIDs: workers, bindings: bindings, command: name,
            process: process, project: location, framework: framework, hiddenReason: hidden
        )
    }
}
