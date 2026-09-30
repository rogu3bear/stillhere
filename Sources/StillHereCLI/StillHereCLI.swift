import Foundation
import StillHereCore

@main
enum StillHereCLI {
    static let usage = """
    stillhere \(StillHereVersion.current): local dev servers, traced to their project, branch and agent.

    USAGE
      stillhere [list]       list running dev servers (default)
      stillhere open <port>  open a server in the default browser
      stillhere stop <port>  stop a server (SIGTERM; asks first)
      stillhere wait <port>  wait until a server answers HTTP, print its URL
      stillhere sessions     agent sessions, their checkouts, and collisions
      stillhere mcp          run as an MCP server on stdio (for coding agents)
      stillhere help <command>

    \(ListCommand.usage)

    \(StopCommand.usage)

    \(WaitCommand.usage)

    \(SessionsCommand.usage)
    """

    static func main() async {
        exit(await run(Array(CommandLine.arguments.dropFirst())))
    }

    static func run(_ arguments: [String], output: Output = Output()) async -> Int32 {
        let command = arguments.first ?? "list"
        let rest = Array(arguments.dropFirst())
        do {
            switch command {
            case "list", "ls": return try await ListCommand(rest, output: output).run()
            case "open": return try await OpenCommand(rest, output: output).run()
            case "stop": return try await StopCommand(rest, output: output).run()
            case "wait": return try await WaitCommand(rest, output: output).run()
            case "sessions": return try await SessionsCommand(rest, output: output).run()
            case "mcp":
                guard rest.isEmpty else { throw Arguments.UsageError(description: "mcp takes no arguments") }
                await MCPServer().serve()
                return 0
            case "help", "-h", "--help":
                output.line(help(for: rest.first))
                return 0
            case "version", "--version", "-v":
                output.line(StillHereVersion.current)
                return 0
            default:
                // Bare flags mean `list` (`stillhere --json`).
                if command.hasPrefix("--") { return try await ListCommand(arguments, output: output).run() }
                throw Arguments.UsageError(description: "unknown command '\(command)'")
            }
        } catch let error as Arguments.UsageError {
            output.error("\(error.description)\n\n\(help(for: command))")
            return 2
        } catch {
            output.error(String(describing: error))
            return 1
        }
    }

    static func help(for command: String?) -> String {
        switch command {
        case "list", "ls": ListCommand.usage
        case "open": OpenCommand.usage
        case "stop": StopCommand.usage
        case "wait": WaitCommand.usage
        case "sessions": SessionsCommand.usage
        default: usage
        }
    }
}
