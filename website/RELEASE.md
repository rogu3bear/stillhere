# term-web v0.1.0 public release

`0.1.0` is the first planned public version. Earlier `0.3.x` source versions
were internal development versions; existing Git history and old artifacts are
preserved. Native `VERSION`, `TermWebVersion.current`, and the website Cargo
package version must agree before publication.

## Local qualification

- `../scripts/check-version-sync.sh`
- `swift test` from the native repository root
- `./scripts/verify.sh` from this website directory
- Inspect the actual Worker-rendered home, screens, all seven guide pages,
  privacy, and 404 routes. Traverse the guide and verify its deep links.
- Exercise navigation and keyboard focus after hydration and without WASM.
- Inspect mobile, intermediate, XL (1280), XXL (1536), and XXXL (1920+) layouts.
- Verify the product screenshot comes from current native SwiftUI views.

The inherited template verifiers remain required. The final dry run uses the
ignored local artifact config snapshot after the full build; it preserves
runtime settings while omitting the redundant custom-build subprocess. Its recipe sources are
reference material; no recipe routes or server functions are exposed by the
public site. Source, native tests, Worker build, browser inspection, installer
qualification, and provider readback are separate proof planes.

## Installer

Build a fresh `dist/term-web-0.1.0.pkg` with the native repository's packaging
script. Preserve older versioned packages. Verify signature and payload through
the existing package checks. Apple notarization and Gatekeeper acceptance are
required before advertising an ordinary public installer. Once qualified,
place the exact artifact in the approved download location and update the
installer card to its verified URL; test the download in a browser.

## Cloudflare

Use `cfctl` through the registered Cloudflare Authority. Bind the intended
Pages project, account, generated `pages.dev` hostname, source and built assets,
permissions, rollback, and exact approved plan before a provider mutation.
Do not provision D1 merely because the inherited template declares a placeholder;
these product pages do not query it. Resolve that binding with the Authority
before any provider change. Keep provider identities and credentials
out of tracked source. The canonical local Worker retains
`main = "build/_worker.js"` and `ASSETS`.

After the full Worker gate passes, run `bun scripts/export-pages.mjs` against
the local preview. Inspect the static artifact in a local Pages preview,
including the guide, exact screenshots, hydration, CSP, and unknown-route 404.
The public artifact is static: it does not include the Worker, Functions,
session cookies, D1, or secret bindings. Record its complete file inventory and
SHA-256 digest from `var/pages-export.json` alongside the exact source revision.
The local inventory is not a cfctl authenticated reproduction receipt.
Do not present a deployment commit hash as proof of uncommitted source bytes.

Local preview uses Wrangler, but provider operations, publication, and live
readback use `cfctl`. A source build or dry run does not establish publication.

## Remaining release inputs

The user selected a Pages deployment; use the generated hostname without a
custom-domain prerequisite. Account/project binding, registered Authority
clearance, and the exact cfctl plan remain provider prerequisites. The existing
Apple notarytool keychain profile is needed only for the separate installer;
it does not block publishing the site with its honest availability notice.
Do not acquire credentials or present an unqualified package as a public download.
