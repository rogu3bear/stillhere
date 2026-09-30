/// Lists listeners with `lsof -nP -iTCP -sTCP:LISTEN -F pcRtn`.
public struct LsofListenerSource: ListenerSource {
    public static let executable = "/usr/sbin/lsof"
    public static let arguments = ["-nP", "-iTCP", "-sTCP:LISTEN", "-F", "pcRtn"]

    private let runner: any CommandRunner
    private let timeout: Duration

    public init(runner: any CommandRunner = Subprocess(), timeout: Duration = .seconds(5)) {
        self.runner = runner
        self.timeout = timeout
    }

    public func listeners() async throws -> [ListenerRecord] {
        let output = try await runner.run(Self.executable, Self.arguments, timeout: timeout)
        switch output.status {
        case 0:
            return LsofListenParser.parse(output.text)
        case 1:
            // lsof exits 1 when nothing matches, and also when it could not
            // inspect some processes; whatever it printed is still valid.
            return output.stdout.isEmpty ? [] : LsofListenParser.parse(output.text)
        default:
            throw DetectionError.commandFailed(executable: Self.executable, status: output.status)
        }
    }
}
