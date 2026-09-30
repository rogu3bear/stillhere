# Where term-web could go next

These are product proposals, not v0.1.0 features or public roadmap promises.
The starting point is the shipped detector, native menu, CLI, MCP tools, and
process identity checks. No new feature below has been implemented in this pass.

## The opportunity

Development leaves a lot of state outside the code: a preview in one terminal,
a server from an old worktree, an agent sharing a checkout, a port occupied by
something nobody remembers starting. term-web already makes some of that state
visible and actionable. The next step is to explain what changed, who owns it,
and what a person or agent should do next.

There is no measured demand, pricing evidence, or adoption baseline yet. The
priorities below are my product judgment, grounded in current capabilities and
their limits.

| Idea | The user moment | A small first version | How to judge it |
| --- | --- | --- | --- |
| **Finish-session review** | “The agent is done. What’s still running?” | Show that session’s identifiable servers, let the user keep or stop each, then report the observed result. | A person cleans up the intended preview without affecting another session. |
| **What changed?** | “This worked a minute ago. What happened?” | An opt-in local timeline of observed starts, exits, readiness responses, and ownership changes. No prompts, full environments, or captured terminal output. | A user can trace a port change without reconstructing terminal history. |
| **Workspace view** | “Which preview belongs to this branch?” | Group current servers and sessions by exact checkout/worktree, with Open, Reveal, Terminal, and existing Stop actions. | Users open the intended checkout and identify a leftover server faster. |
| **Port handoff** | “I need 3000, but something else has it.” | A preflight explaining the current listener, its owner, and whether reuse or an explicitly confirmed stop is possible. No automatic eviction. | A user resolves a conflict without stopping the wrong project. |
| **Explicit agent ownership** | “Which chat actually started this?” | An opt-in launch wrapper or client integration that records a session identity alongside verified process identity. Unknown ownership stays unknown. | Distinct chats sharing a host can attribute their own launched servers; an untrusted claim cannot seize another server. |

## My first pick: finish-session review

It completes the existing promise: find it, understand it, take it out. Start
with a review screen and one confirmed stop at a time, using known ownership.
Keep the default behavior unchanged: closing a chat does not kill processes.

The review should show the project, branch, port, agent evidence, and current
process identity. “Keep” means leave it running; “Stop” uses the established
identity checks. The result should distinguish stopped, replaced by a watcher,
still running, refused, and could not inspect. Closing the review must not
imply that cleanup succeeded.

A small prototype could reuse existing sample-server fixtures before touching
real processes. An opt-in workflow can then be assessed on deliberately started
test servers. Automatic scheduling and batch force kill are unnecessary for
that first version.

## The enabling investment: explicit ownership

Today, caller ownership comes from Claude Code markers. Codex desktop chats
share a host process, so the detector cannot distinguish those chats for
collision detection. Naming an agent is also not the same as proving the
calling session owns its server.

Any wrapper or integration must bind the caller/session, launched process,
start time, and checkout. It must survive PID reuse without transferring
authority, and a stale or unverifiable record must not permit a signal. An
arbitrary process should not be able to claim another process simply by writing
an ownership file. This needs a deliberate trust model before implementation.

That investment could make finish-session review, handoff, and per-chat context
work across clients. It should come before promising universal agent cleanup.

## A larger direction to explore

“What is going on on my development machine?” is a stronger question than
“Which ports are open?” A workspace view plus a local event timeline could
become a useful daily starting point: current previews, their owners, recent
changes, and unresolved conflicts. Start with observed facts and the existing
actions. Do not imply that this includes CPU accounting, cost estimates,
container inspection, log collection, remote hosts, or restart orchestration.

The first research should be a few real cleanup sessions: what does the person
look for, what do they keep, what still surprises them, and when does the app
lack enough evidence to act? That evidence should choose the next feature.

## Current foundations

- `Sources/TermWebCore/Actions/ServerStopper.swift`: verified single-process Stop.
- `Sources/TermWebApp/Stores/StopFlow.swift`: native confirmation and escalation.
- `Sources/TermWebCore/Reporting/ServerReport.swift`: server context and evidence.
- `Sources/TermWebCLI/MCP/MCPTools.swift`: caller ownership and four MCP tools.
- `Sources/TermWebCore/Sessions/SessionScanner.swift`: session/checkouts inference.
