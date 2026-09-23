# term-web

A macOS menu bar app that finds the dev servers running on your Mac and lists
them in one dropdown. The menu bar icon shows how many are running.

Each row shows:

- the port and URL (`http://localhost:<port>/`)
- the process name and PID
- the project folder (the process's working directory; hover for the full path)
- a framework guess (Vite, Next.js, Astro, Remix, Rails, Django, Flask,
  FastAPI/uvicorn, Bun, Node, Python `http.server` and more)
- uptime
- HTTP status and page title, from a quick GET to the loopback address

Row actions: **Open** in the default browser, **Copy URL**, **Reveal** the
project in Finder, open the project folder in **Terminal**, and **Stop**. Stop
asks for confirmation and sends SIGTERM. If the process is still running about
3 seconds later, it offers SIGKILL. Each signal goes to one process (the
server's root process, never a process group), and only after checking that its
start time has not changed, so a reused PID is never signalled.

The list refreshes on a timer and whenever you open the menu. IPv4 and IPv6
listeners on the same port appear as one entry.

## Requirements

- macOS 26 or later
- Apple silicon (arm64)

## Install

Open `term-web-<version>.pkg` and follow the installer. It installs
`/Applications/term-web.app`. Then open term-web from Applications. It runs in
the menu bar only, with no Dock icon. Use **Quit** in the dropdown to exit.

Until the package is notarized, Gatekeeper blocks it by default. See
[Notarization](#notarization).

## Privacy

- term-web makes no network connections except HTTP requests to `127.0.0.1`
  and `::1` on the ports it found. There is no telemetry.
- It has no entitlements and asks for no special permissions. It runs with the
  hardened runtime.
- It only sees processes that belong to you. Listeners owned by root or other
  users are skipped.
- To guess a framework, it reads `package.json`, `Gemfile`, `pyproject.toml`
  and similar files near a server's working directory. If a project lives under
  Documents, Desktop, Downloads or iCloud Drive, macOS may ask once whether
  term-web can access that folder. Declining only makes the framework guess less
  specific.

## How detection works

Detection lives in the `TermWebCore` library, separate from the UI, and runs
off the main thread.

1. `lsof -nP -iTCP -sTCP:LISTEN -F pcRtn` lists your TCP listening sockets.
2. Sockets are grouped by port, so IPv4 and IPv6 become one entry and a forked
   parent and its workers become one server.
3. Process details (working directory, start time, parent PID, full argv) come
   from `libproc` and `sysctl(KERN_PROCARGS2)`.
4. A classifier hides system and non-dev listeners. A framework detector reads
   the command line, then the nearest project manifest, then HTTP response
   headers.
5. Visible servers get a short HTTP probe (status and `<title>`).

**Why libproc rather than `lsof -p <pid> -d cwd` for process details.** The
text path (`lsof -a -p PIDS -d cwd -Fn` plus `ps`) was measured at about 180 ms
of process spawning per refresh, compared with about 0.2 ms for libproc. More
importantly, `ps` cannot give an exact process start time, which Stop needs to
avoid signalling a reused PID, and it cannot give exact argv, because Next.js
rewrites its process title and `ps` joins arguments with spaces. The lsof-based
inspector is still implemented and tested as `LsofProcessInspector`.

## Hidden servers and the ignore list

These are hidden by default:

- executables under `/System`, `/usr/libexec`, `/usr/sbin` or `/Library/Apple`
- daemons whose working directory is `/` (ControlCenter/AirPlay, rapportd)
- helper processes inside other `.app` bundles
- processes named in the ignore list: ControlCenter, rapportd, sharingd,
  postgres, mysqld, redis-server, mongod, Dropbox, Spotify, `Code Helper*` and
  others. A trailing `*` matches a prefix.
- well-known database and broker ports: 5432, 3306, 6379, 27017, 11211, 9200,
  9300, 5672, 15672, 2379, 4222, 8123

Interpreters (`node`, `bun`, `deno`, `python*`, `ruby`, `php`, `java`) are
never hidden by the first three rules. Ports 5000 and 7000 are not on the port
list, because Flask uses 5000. AirPlay is hidden by process name instead.

Edit these in **Settings > Ignore List**. **Reset to Defaults** restores them.
Turn on **Show hidden servers** in **Settings > General** to list hidden
entries in their own section, each labelled with the reason it was hidden.

## Settings

- **Refresh every:** 2, 3, 5 (default), 10 or 30 seconds
- **Show hidden servers**
- **Check HTTP status and page title**
- **Launch at login:** uses `SMAppService`. Register it only from
  `/Applications/term-web.app`. A copy run from `build/` registers that path
  instead. If macOS needs approval, the Settings window links to Login Items.

## Build from source

Requires Xcode 26 or later (Swift 6.2 or later).

```sh
swift build                  # debug build
swift test                   # unit tests (fake lsof output, no live processes)
scripts/bundle.sh --dev      # build/term-web.app, ad-hoc signed for local runs
open build/term-web.app
```

The project uses Swift Package Manager only. There is no Xcode project, because
SwiftPM builds the executable and the scripts assemble the `.app` bundle.

The version lives only in `VERSION`. `bundle.sh` stamps it into the app's
`Info.plist`, and `package.sh` uses it for the package version and file name.
The minimum macOS (26.0) is set in `Package.swift`, `scripts/common.sh`,
`Packaging/Info.plist` and `Packaging/distribution.xml`.
`scripts/check-version-sync.sh` runs as part of every bundle build and fails if
those differ.

`scripts/make-icon.sh` regenerates `Packaging/AppIcon.icns` from
`scripts/make-icon.swift`. The generated icon is committed.

## Packaging

```sh
scripts/package.sh [--force] [--notary-profile NAME]
```

This script:

1. builds a release arm64 binary and bundles `build/term-web.app`
2. signs it with Developer ID Application, using the hardened runtime and a
   secure timestamp, with no entitlements
3. builds a component package that installs to `/Applications`
4. builds a product archive from `Packaging/distribution.xml` (title, arm64
   host requirement, minimum macOS 26.0) and signs it with Developer ID
   Installer
5. writes `dist/term-web-<VERSION>.pkg` and a `.sha256` file next to it
6. runs checks: `codesign --verify --deep --strict` on the app and on a copy
   extracted from the package, `pkgutil --check-signature`, a check that the
   payload contains `./term-web.app/Contents/MacOS/term-web` with install
   location `/Applications`, and `spctl --assess`

The script will not overwrite an existing package for the same version. Bump
`VERSION`, delete the file, or pass `--force`.

Signing identities default to the MLNavigator Inc. (team 4JB58L7BTZ)
certificates. Override them with `APP_SIGN_ID` and `INSTALLER_SIGN_ID`, set to a
SHA-1 hash or a full certificate name from `security find-identity -v`.

Expected results before notarization: `spctl` rejects both the app and the
package with `source=Unnotarized Developer ID` (exit 3). The script reports this
and carries on.

**AppleDouble entries.** When the package is built from a sandboxed shell, such
as an agent's terminal, the files carry a `com.apple.provenance` extended
attribute that cannot be removed there. pkgbuild then stores `._*` entries in
the payload and may print `write: Permission denied`. The extracted app still
verifies, so the signature is unaffected, but build release packages from a
normal Terminal session and check that `pkgutil --payload-files` shows no `._`
entries.

## Notarization

Notarization runs only when you name a notarytool keychain profile. Without
one, `package.sh` sends nothing to Apple and prints these steps.

```sh
# once: store credentials with an app-specific password...
xcrun notarytool store-credentials <profile> --apple-id <apple-id> --team-id 4JB58L7BTZ
# ...or with an App Store Connect API key
xcrun notarytool store-credentials <profile> --key AuthKey_XXXX.p8 --key-id <id> --issuer <uuid>

scripts/package.sh --force --notary-profile <profile>
```

With a profile, the script runs `notarytool submit --wait`, staples the ticket
to the package, validates the staple, and reruns `spctl`, which should then
report `source=Notarized Developer ID`. You can also set the profile with the
`NOTARY_PROFILE` environment variable.

## Troubleshooting

- **The Settings window opens behind other windows.** A menu bar app is not
  the active app when its panel closes. term-web activates itself before opening
  Settings. If the window still ends up behind others, click the term-web
  menu bar icon again or use Mission Control to bring it forward.
- **A server is missing.** Turn on **Show hidden servers** to see whether it
  was hidden and why, then edit the ignore list. Servers run by root or another
  user cannot be seen.
- **The status shows an error or timeout.** The probe waits only briefly. Some
  servers answer slowly on their first request. The next refresh tries again.
- **Launch at login does nothing.** Install the app into `/Applications` first,
  then turn the setting on again. Check System Settings > General > Login Items.

## License

© 2026 MLNavigator Inc. All rights reserved.
