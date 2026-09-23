import Foundation
import TermWebCore

/// The MCP tools: list, wait for and stop local dev servers.
struct MCPTools: Sendable {
    /// The agent session this server runs in (inherited from Claude Code), used for
    /// `mine` and for the stop ownership rule.
    var callerSession: String? = CallerSession.id
    var query = ServerQuery()
    var stopper = ServerStopper()
    var maxWait: Double = 120

    static let definitions: [JSONValue] = [
        [
            "name": "list_servers",
            "title": "List dev servers",
            "description": "Lists dev servers listening on this Mac with URL, framework, project, git branch/worktree, the coding agent session that started each one (and whether that session has ended: orphaned), uptime and HTTP status/title.",
            "inputSchema": [
                "type": "object",
                "properties": [
                    "mine": ["type": "boolean", "description": "Only servers started by this agent session."],
                    "orphans_only": ["type": "boolean", "description": "Only servers whose launching agent session has ended."],
                    "include_hidden": ["type": "boolean", "description": "Include system and helper listeners hidden by default."],
                    "port": ["type": "integer", "minimum": 1, "maximum": 65535],
                ],
                "additionalProperties": false,
            ],
            "annotations": ["readOnlyHint": true, "openWorldHint": false],
        ],
        [
            "name": "wait_for_server",
            "title": "Wait for a dev server",
            "description": "Waits until a port is listening and answering HTTP (any status), then returns the server. Use right after starting a dev server instead of sleeping.",
            "inputSchema": [
                "type": "object",
                "properties": [
                    "port": ["type": "integer", "minimum": 1, "maximum": 65535],
                    "timeout_seconds": ["type": "number", "minimum": 0, "maximum": 120, "description": "Default 30."],
                    "require_http": ["type": "boolean", "description": "Default true. False waits only for the listener."],
                ],
                "required": ["port"],
                "additionalProperties": false,
            ],
            "annotations": ["readOnlyHint": true, "openWorldHint": false],
        ],
        [
            "name": "stop_server",
            "title": "Stop a dev server",
            "description": "Stops the server on a port with SIGTERM, verifying the exact process first. Only servers started by this agent session unless any_owner is true. System and helper processes are never stopped.",
            "inputSchema": [
                "type": "object",
                "properties": [
                    "port": ["type": "integer", "minimum": 1, "maximum": 65535],
                    "pid": ["type": "integer", "description": "Required when unrelated processes share the port."],
                    "force": ["type": "boolean", "description": "Send SIGKILL to the same process if SIGTERM didn't stop it."],
                    "any_owner": ["type": "boolean", "description": "Allow stopping servers this session did not start (the user's own, or another agent's)."],
                ],
                "required": ["port"],
                "additionalProperties": false,
            ],
            "annotations": ["readOnlyHint": false, "destructiveHint": true, "idempotentHint": true, "openWorldHint": false],
        ],
    ]

    func call(_ params: JSONValue) async throws -> JSONValue {
        guard let name = params["name"]?.stringValue else {
            throw RPCFailure(code: -32602, message: "Invalid params: missing tool name")
        }
        let arguments = params["arguments"] ?? [:]
        switch name {
        case "list_servers": return try await list(arguments)
        case "wait_for_server": return try await wait(arguments)
        case "stop_server": return try await stop(arguments)
        default: throw RPCFailure(code: -32602, message: "Unknown tool: \(name)")
        }
    }

    func list(_ arguments: JSONValue) async throws -> JSONValue {
        var filter = ServerQuery.Filter(
            includeHidden: arguments["include_hidden"]?.boolValue ?? false,
            orphansOnly: arguments["orphans_only"]?.boolValue ?? false,
            port: try port(arguments, required: false)
        )
        if arguments["mine"]?.boolValue == true {
            guard let callerSession else {
                return Self.toolError("mine=true needs the MCP server to run inside a Claude Code session (CLAUDE_CODE_SESSION_ID is not set).")
            }
            filter.sessionID = callerSession
        }
        let reports = try await query.reports(filter)
        return try Self.toolResult(["servers": JSONValue(encoding: reports)])
    }

    func wait(_ arguments: JSONValue) async throws -> JSONValue {
        let port = try port(arguments, required: true)!
        let timeout = min(max(arguments["timeout_seconds"]?.doubleValue ?? 30, 0), maxWait)
        let requireHTTP = arguments["require_http"]?.boolValue ?? true
        let outcome = await ServerWaiter(query: query).wait(port: port, timeout: .seconds(timeout), requireHTTP: requireHTTP)
        let server = try outcome.entry.map { try JSONValue(encoding: ServerReport(entry: $0, probe: outcome.probe, now: Date())) }
        return try Self.toolResult([
            "ready": .bool(outcome.ready),
            "waited_ms": .number(Double(outcome.waited.milliseconds)),
            "server": server ?? .null,
        ], isError: !outcome.ready)
    }

    func stop(_ arguments: JSONValue) async throws -> JSONValue {
        let port = try port(arguments, required: true)!
        var found = try await query.entries(.init(includeHidden: true, port: port))
        if let pid = arguments["pid"]?.intValue { found = found.filter { $0.rootPID == Int32(pid) } }
        guard found.count == 1, let entry = found.first else {
            let message = found.isEmpty
                ? "Nothing matching is listening on port \(port)."
                : "Unrelated processes share port \(port) (PIDs \(found.map { String($0.rootPID) }.joined(separator: ", "))); pass pid."
            return Self.toolError(message)
        }
        let anyOwner = arguments["any_owner"]?.boolValue ?? false
        if !anyOwner, callerSession == nil || entry.agent?.sessionID != callerSession {
            return Self.toolError("Port \(port) was not started by this agent session, so it was not stopped. Ask the user, then pass any_owner=true.")
        }
        let result = await stopper.stop(entry, force: arguments["force"]?.boolValue ?? false)
        return try Self.toolResult([
            "stopped": .bool(result.succeeded),
            "message": .string(result.message),
            "port": .number(Double(port)),
            "pid": .number(Double(entry.rootPID)),
        ], isError: !result.succeeded)
    }

    private func port(_ arguments: JSONValue, required: Bool) throws -> Int? {
        guard let raw = arguments["port"] else {
            if required { throw RPCFailure(code: -32602, message: "Invalid params: port is required") }
            return nil
        }
        guard let port = raw.intValue, (1...65_535).contains(port) else {
            throw RPCFailure(code: -32602, message: "Invalid params: port must be an integer 1-65535")
        }
        return port
    }

    /// Tool results carry the data twice: `structuredContent` for clients that read it and
    /// a JSON text block for those that only show text.
    static func toolResult(_ structured: [String: JSONValue], isError: Bool = false) throws -> JSONValue {
        let text = String(decoding: try ServerReport.encoder().encode(JSONValue.object(structured)), as: UTF8.self)
        return [
            "content": [["type": "text", "text": .string(text)]],
            "structuredContent": .object(structured),
            "isError": .bool(isError),
        ]
    }

    static func toolError(_ message: String) -> JSONValue {
        ["content": [["type": "text", "text": .string(message)]], "isError": true]
    }
}
