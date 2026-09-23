/// Pure parser for `sysctl KERN_PROCARGS2` bytes:
/// `argc` (Int32, host order) + exec path + NUL padding + argv[0..<argc] (NUL separated) + env.
/// The environment is never read.
public enum ProcArgsParser {
    public struct Arguments: Sendable, Hashable {
        public var executablePath: String
        public var argv: [String]
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
        return Arguments(executablePath: executablePath, argv: argv)
    }
}
