use super::docs_layout::DocsLayout;
use super::product::CodeBlock;
use leptos::prelude::*;
use leptos_meta::Title;

#[component]
pub fn AgentGuidePage() -> impl IntoView {
    view! {
        <Title text="Coding agents — term-web"/>
        <DocsLayout active="agents">
            <p class="eyebrow">"CODING AGENTS"</p><h1>"Give your agent"<br/>"a view of localhost."</h1>
            <p class="doc-lead">"Before starting another server, an agent can see what is already there. After starting one, it can wait for an actual response. When finished, it can clean up the server it owns."</p>
            <section id="mcp"><h2>"Connect the local MCP server"</h2><p>"term-web mcp runs over stdio. Your client launches a local process; there is no hosted term-web endpoint to configure. Make sure the client can find the executable."</p>
                <h3>"Claude Code"</h3><CodeBlock label="Available across your projects" code="claude mcp add --transport stdio --scope user term-web -- term-web mcp\nclaude mcp get term-web"/><p>"Use Claude Code’s /mcp view to check the connection. To keep the configuration local to the current project, omit --scope user."</p>
                <h3>"Codex"</h3><p>"Add this table to ~/.codex/config.toml, preserving the rest of your configuration. If the client cannot resolve term-web, use the executable’s absolute path as command."</p><CodeBlock label="~/.codex/config.toml" code="[mcp_servers.term-web]\ncommand = \"term-web\"\nargs = [\"mcp\"]"/>
                <p>"Client configuration does not grant term-web new ownership information. Listing and waiting work without a recognized caller; session-scoped filtering and default stopping need Claude Code’s inherited session markers. A Codex connection alone does not establish that a server belongs to the current chat."</p>
            </section>
            <section id="tools"><h2>"The four tools"</h2><dl class="doc-definitions">
                <div><dt>"list_servers"</dt><dd>"Inventory with project, git context, agent evidence, HTTP response, and stop eligibility. Filters: mine, orphans_only, include_hidden, and port."</dd></div>
                <div><dt>"list_sessions"</dt><dd>"Agents, their checkouts and servers, collisions, and caller_pid when known. include_idle adds sessions with no detected checkout."</dd></div>
                <div><dt>"wait_for_server"</dt><dd>"Required port, optional timeout_seconds (0–120, default 30), and require_http (default true). Any HTTP status means it answered. Results include ready, waited_ms, and server."</dd></div>
                <div><dt>"stop_server"</dt><dd>"Required port; optional pid, force, and any_owner. A PID is required for an ambiguous port. force tries SIGTERM before SIGKILL. The default requires caller ownership; any_owner bypasses that ownership restriction after the agent asks you, while process protections remain."</dd></div>
            </dl><p>"Tool replies carry both structuredContent and a JSON text representation. Check isError and the returned result: requested is not the same as stopped, and a timed-out wait is not readiness."</p></section>
            <section id="workflow"><h2>"A useful instruction for your agent"</h2><CodeBlock label="Suggested project instruction" code="Before starting a preview, use term-web to inspect existing servers.\nCheck its project and branch before reusing it.\nAfter starting a server, wait for its response with wait_for_server.\nWhen finished, stop only a server this session owns and no longer needs.\nAsk me before using any_owner or stopping another session’s server.\nRead back the stop result and report anything still running."/><p>"These are instructions you can give the agent, not automation installed by the app. term-web does not automatically shut down servers when a chat ends."</p></section>
            <section id="collisions"><h2>"Warn before independent writers collide"</h2><p>"Merge this SessionStart hook into your existing Claude Code settings at ~/.claude/settings.json or .claude/settings.json. Preserve other hooks; do not replace the entire file."</p><CodeBlock label="Claude Code settings fragment" code="{\n  \"hooks\": {\n    \"SessionStart\": [{\n      \"hooks\": [{\n        \"type\": \"command\",\n        \"command\": \"term-web sessions --check\"\n      }]\n    }]\n  }\n}"/><p>"The check adds a note when another independent writer is already in the caller’s checkout. It always exits 0 and does not block the session. Parent sessions and their workers do not collide; explicitly read-only or review sessions do not count as writers."</p><p>"The Codex desktop app hosts its chats under one app server. term-web cannot distinguish two such chats for collision detection. A collision warning also cannot tell which files either session intends to edit."</p></section>
            <section id="attribution"><h2>"What ownership is based on"</h2><p>"Attribution uses selected inherited agent markers and live ancestor processes. Claude Code’s session ID and launcher PID support session matching. Other named agents can be detected through markers or ancestry without necessarily supplying a session identity."</p><p>"A server is called orphaned only when a known launcher PID has ended or was reused. No launcher identity means unknown liveness, not an orphan guess."</p><a class="text-link" href="/privacy">"What the app reads →"</a></section>
            <section><h2>"Client references"</h2><p>"For client-specific configuration and hook behavior, see the official sources:"</p><ul><li><a href="https://code.claude.com/docs/en/mcp">"Claude Code MCP configuration"</a></li><li><a href="https://code.claude.com/docs/en/hooks#sessionstart">"Claude Code SessionStart hooks"</a></li><li><a href="https://github.com/openai/codex/blob/main/codex-rs/core/config.schema.json">"Codex configuration schema"</a></li></ul></section>
        </DocsLayout>
    }
}
