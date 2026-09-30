import Foundation
import StillHereCore

/// A dual-era MCP server over stdio: newline-delimited JSON-RPC 2.0.
/// - Modern (2026-07-28+): stateless; every request carries its protocol version and
///   client capabilities in `_meta`; `server/discover` describes the server.
/// - Legacy (2025-11-25 and earlier): an `initialize` handshake, then plain requests.
struct MCPServer {
    static let modernVersions = ["2026-07-28"]
    static let legacyVersions = ["2025-11-25", "2025-06-18", "2025-03-26", "2024-11-05"]
    static var supportedVersions: [String] { modernVersions + legacyVersions }

    static let instructions = """
    stillhere sees every dev server listening on this Mac, with its project, git branch and \
    the coding agent session that started it. After starting a dev server, call \
    wait_for_server instead of sleeping. Use list_servers with mine=true to see the servers \
    this session started, and stop them with stop_server before you finish unless the user \
    wants them kept running. Call list_sessions before editing files if another agent \
    session may be working in the same checkout.
    """

    let tools: MCPTools

    init(tools: MCPTools = MCPTools()) {
        self.tools = tools
    }

    static var serverInfo: JSONValue {
        ["name": "stillhere", "version": .string(StillHereVersion.current)]
    }

    /// Reads stdin until EOF. Requests run concurrently (a long wait_for_server must not
    /// block a ping); responses are written whole, one per line.
    func serve() async {
        let writer = LineWriter()
        await withTaskGroup(of: Void.self) { group in
            do {
                // Split on LF bytes only: `AsyncLineSequence` also breaks on U+2028/U+2029,
                // which JSON allows unescaped inside strings.
                var buffer: [UInt8] = []
                func dispatch(_ bytes: [UInt8]) {
                    var bytes = bytes
                    if bytes.last == UInt8(ascii: "\r") { bytes.removeLast() }
                    guard !bytes.isEmpty else { return }
                    let line = String(decoding: bytes, as: UTF8.self)
                    group.addTask {
                        if let response = await handle(line: line) { await writer.write(response) }
                    }
                }
                for try await byte in FileHandle.standardInput.bytes {
                    if byte == UInt8(ascii: "\n") {
                        dispatch(buffer)
                        buffer.removeAll(keepingCapacity: true)
                    } else {
                        buffer.append(byte)
                    }
                }
                dispatch(buffer)
            } catch {
                FileHandle.standardError.write(Data("stillhere mcp: stdin error: \(error)\n".utf8))
            }
        }
    }

    /// One JSON-RPC message in, at most one response out (notifications get none).
    func handle(line: String) async -> JSONValue? {
        guard let message = try? JSONDecoder().decode(JSONValue.self, from: Data(line.utf8)) else {
            return Self.error(id: .null, code: -32700, message: "Parse error")
        }
        // Batches and non-object messages are not requests (MCP does not use batching).
        guard case .object = message else { return Self.error(id: .null, code: -32600, message: "Invalid Request") }
        let id = message["id"]
        guard let method = message["method"]?.stringValue else {
            return id.map { Self.error(id: Self.isValidID($0) ? $0 : .null, code: -32600, message: "Invalid Request") }
        }
        guard let id else { return nil } // notification
        guard Self.isValidID(id) else { return Self.error(id: .null, code: -32600, message: "Invalid Request: id must be a string or integer") }
        let params = message["params"] ?? [:]
        do {
            return Self.result(id: id, try await dispatch(method: method, params: params))
        } catch let failure as RPCFailure {
            return Self.error(id: id, code: failure.code, message: failure.message, data: failure.data)
        } catch {
            return Self.error(id: id, code: -32603, message: "Internal error: \(error)")
        }
    }

    func dispatch(method: String, params: JSONValue) async throws -> JSONValue {
        if method == "initialize" { return Self.initializeResult(params) }
        let modern = try Self.validateModernMeta(params)
        var result: JSONValue
        switch method {
        case "server/discover": result = Self.discoverResult()
        case "ping": result = [:]
        case "tools/list": result = ["tools": .array(MCPTools.definitions)]
        case "tools/call": result = try await tools.call(params)
        default: throw RPCFailure(code: -32601, message: "Method not found: \(method)")
        }
        guard case .object(var object) = result else { return result }
        object["resultType"] = "complete"
        // Discovery always identifies the server: clients probe with it before choosing an era.
        if modern || method == "server/discover" {
            object["_meta"] = ["io.modelcontextprotocol/serverInfo": Self.serverInfo]
        }
        return .object(object)
    }

    /// MCP request ids are strings or integers, never null.
    static func isValidID(_ id: JSONValue) -> Bool {
        switch id {
        case .string: true
        case .number: id.intValue != nil
        default: false
        }
    }

    /// true for a modern request; legacy requests (no protocol version in `_meta`) pass.
    static func validateModernMeta(_ params: JSONValue) throws -> Bool {
        guard let meta = params["_meta"], let version = meta["io.modelcontextprotocol/protocolVersion"] else {
            return false
        }
        guard let requested = version.stringValue, supportedVersions.contains(requested) else {
            throw RPCFailure(
                code: -32022,
                message: "Unsupported protocol version",
                data: ["supported": .array(supportedVersions.map(JSONValue.string)), "requested": version]
            )
        }
        guard meta["io.modelcontextprotocol/clientCapabilities"] != nil else {
            throw RPCFailure(code: -32602, message: "Invalid params: _meta lacks io.modelcontextprotocol/clientCapabilities")
        }
        return true
    }

    static func initializeResult(_ params: JSONValue) -> JSONValue {
        let requested = params["protocolVersion"]?.stringValue
        let version = requested.flatMap { legacyVersions.contains($0) ? $0 : nil } ?? legacyVersions[0]
        return [
            "protocolVersion": .string(version),
            "capabilities": ["tools": [:]],
            "serverInfo": serverInfo,
            "instructions": .string(instructions),
        ]
    }

    static func discoverResult() -> JSONValue {
        [
            "supportedVersions": .array(supportedVersions.map(JSONValue.string)),
            "capabilities": ["tools": [:]],
            "instructions": .string(instructions),
        ]
    }

    static func result(id: JSONValue, _ result: JSONValue) -> JSONValue {
        ["jsonrpc": "2.0", "id": id, "result": result]
    }

    static func error(id: JSONValue, code: Int, message: String, data: JSONValue? = nil) -> JSONValue {
        var error: [String: JSONValue] = ["code": .number(Double(code)), "message": .string(message)]
        if let data { error["data"] = data }
        return ["jsonrpc": "2.0", "id": id, "error": .object(error)]
    }
}

struct RPCFailure: Error {
    var code: Int
    var message: String
    var data: JSONValue?
}

/// Serializes whole-line writes to stdout from concurrent request tasks.
actor LineWriter {
    func write(_ message: JSONValue) {
        guard var data = try? ServerReportCoding.encoder.encode(message) else { return }
        data.append(UInt8(ascii: "\n"))
        FileHandle.standardOutput.write(data)
    }
}
