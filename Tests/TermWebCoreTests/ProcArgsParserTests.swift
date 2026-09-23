import Testing
@testable import TermWebCore

@Suite struct ProcArgsParserTests {
    /// Builds KERN_PROCARGS2-shaped bytes: argc, exec path, NUL padding, argv, env.
    static func bytes(argc: Int32, exec: String, padding: Int = 3, argv: [String], env: [String] = ["SECRET=do-not-read"]) -> [UInt8] {
        var result = withUnsafeBytes(of: argc) { Array($0) }
        result += Array(exec.utf8) + Array(repeating: 0, count: padding)
        for arg in argv + env { result += Array(arg.utf8) + [0] }
        return result
    }

    @Test func parsesExecPathAndArgvWithoutEnvironment() throws {
        let raw = Self.bytes(argc: 3, exec: "/usr/local/bin/node", argv: ["node", "/p/node_modules/.bin/vite", "--port"])
        let parsed = try #require(ProcArgsParser.parse(raw))
        #expect(parsed.executablePath == "/usr/local/bin/node")
        #expect(parsed.argv == ["node", "/p/node_modules/.bin/vite", "--port"])
    }

    @Test func keepsArgumentsWithSpacesExact() throws {
        let raw = Self.bytes(argc: 1, exec: "/usr/local/bin/node", padding: 1, argv: ["next-server (v15.0.0)"])
        #expect(try #require(ProcArgsParser.parse(raw)).argv == ["next-server (v15.0.0)"])
    }

    @Test func truncatedBufferYieldsPartialArgv() throws {
        let raw = Self.bytes(argc: 5, exec: "/bin/x", argv: ["a", "b"], env: [])
        #expect(try #require(ProcArgsParser.parse(raw)).argv == ["a", "b"])
    }

    @Test func rejectsTooShortOrNegativeArgc() {
        #expect(ProcArgsParser.parse([1, 0]) == nil)
        #expect(ProcArgsParser.parse(Self.bytes(argc: -1, exec: "/bin/x", argv: [])) == nil)
    }
}
