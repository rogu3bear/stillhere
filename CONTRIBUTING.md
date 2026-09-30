# Contributing to Still Here

Still Here helps people find local development servers, understand their
projects and ownership evidence, and stop a specific process with confirmation.
The menu bar app, CLI, and MCP server share the same detection library.

## Build the Mac app

Use an Apple silicon Mac with macOS 26 or later and Xcode 26 or later
(Swift 6.2 or later).

```sh
git clone https://github.com/rogu3bear/stillhere.git
cd stillhere
swift build
swift test
scripts/bundle.sh --dev
open "build/Still Here.app"
.build/debug/stillhere help
```

The development bundle is signed ad hoc for local use. Building it does not
install a global command, register a login item, or produce a notarized installer.
The public installer remains in preparation.

## Choose the right part

- `Sources/StillHereCore`: discovery, classification, provenance, shared reports,
  saved ignore settings, and process identity checks.
- `Sources/StillHereApp`: the native menu, settings, stores, and actions.
- `Sources/StillHereCLI`: commands, JSON output, and the stdio MCP server.
- `Tests`: deterministic fixtures and behavioral tests.
- `website`: the Leptos product site and user guide. Follow its
  [contributor guide](website/CONTRIBUTING.md) and local verification scripts.

Keep network access restricted to detected loopback servers. Preserve the
process identity checks and confirmation behavior around Stop. Missing agent
attribution stays unknown; do not infer ownership from a convenient label.
Use inert sample projects in screenshots and tests.

## Before a pull request

Run `swift test` and `scripts/check-version-sync.sh` for native changes.
Run `./scripts/verify.sh` from `website` for website changes, then inspect the
affected pages at mobile and desktop widths. Local checks are authoritative;
this repository does not use GitHub Actions.

Describe the concrete problem, resulting behavior, and checks you ran. Add a
behavioral test when a change affects detection, ownership, stopping, or saved
settings. Keep generated bundles, installers, local provider records, and
credentials out of Git. Follow [SECURITY.md](SECURITY.md) for vulnerability
reports. Contributions use GPL-3.0-only; preserve third-party notices.
