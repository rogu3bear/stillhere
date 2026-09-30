/// Pure parser for `sysctl KERN_PROCARGS2` bytes:
/// `argc` (Int32, host order) + exec path + NUL padding + argv[0..<argc] (NUL separated) + env.
/// Of the environment, only `AgentMarkers.environmentKeys` are kept; every other variable
/// (tokens, keys, paths) is skipped without being copied out of the buffer.
public enum ProcArgsParser {
    public struct Arguments: Sendable, Hashable {
        public var executablePath: String
        public var argv: [String]
        /// Allowlisted variables only.
        public var agentEnvironment: [String: String] = [:]
    }

    public static func parse(_ bytes: [UInt8]) -> Arguments? {
        guard bytes.count >= 4 else { return nil }
        let argc = bytes.withUnsafeBytes { $0.loadUnaligned(as: Int32.self) }
        guard argc >= 0, argc < 65_536 else { return nil }

        var index = 4
        let pathStart = index
        while index < bytes.count, bytes[index] != 0 { index += 1 }
        let executablePath = String(decoding: bytes[pathStart..<index], as: UTF8.self)
        while index < bytes.count, bytes[index] == 0 { index += 1 }

        var argv: [String] = []
        argv.reserveCapacity(Int(argc))
        while argv.count < Int(argc), index < bytes.count {
            let start = index
            while index < bytes.count, bytes[index] != 0 { index += 1 }
            argv.append(String(decoding: bytes[start..<index], as: UTF8.self))
            index += 1
        }
        return Arguments(executablePath: executablePath, argv: argv, agentEnvironment: agentEnvironment(bytes, from: index))
    }

    /// Scans `KEY=value` strings after argv, matching the key bytes against the allowlist
    /// before decoding anything, so no other variable's value is ever turned into a String.
    static func agentEnvironment(_ bytes: [UInt8], from start: Int) -> [String: String] {
        var result: [String: String] = [:]
        var index = start
        while index < bytes.count {
            let entryStart = index
            while index < bytes.count, bytes[index] != 0 { index += 1 }
            if index > entryStart,
               let equals = bytes[entryStart..<index].firstIndex(of: UInt8(ascii: "=")) {
                let key = bytes[entryStart..<equals]
                if let match = AgentMarkers.environmentKeyBytes.first(where: { $0.elementsEqual(key) }) {
                    result[String(decoding: match, as: UTF8.self)] =
                        String(decoding: bytes[(equals + 1)..<index], as: UTF8.self)
                }
            }
            index += 1
        }
        return result
    }
}
