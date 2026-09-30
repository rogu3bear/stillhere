# Security Policy

## Supported Versions

The Still Here website is preparing its first public release, v0.1.0. The native
installer is qualified separately. Retained template history does not establish
a supported public Still Here release.

## Reporting a Vulnerability

Open a private security advisory on GitHub if available, or contact the maintainer through the repository owner profile. Do not publish exploit details in a public issue before the maintainer has had a reasonable chance to respond.

## Website Security Model

Public Pages hosting serves a static export of the Leptos SSR pages and the
fingerprinted hydration assets. It has no Pages Functions, database, forms,
account system, or production secrets. The export generates a CSP with hashes
for the exact inline hydration scripts, plus anti-framing, `nosniff`, and
referrer headers. A real `404.html` prevents unknown addresses from becoming
successful SPA responses. Fonts and screenshots are self-hosted.

The local Worker retains the following template protections for qualification.
They are reference facilities, not claims that the static public site uses D1
or session cookies.

The starter intentionally ships with:

- placeholder Cloudflare and D1 identifiers
- no committed secrets
- `HttpOnly` session cookies for demo data ownership
- D1 queries scoped by browser session
- bounded server-function request bodies
- CSP, anti-framing, `nosniff`, referrer policy, and no-store dynamic responses
- hashed immutable static assets served through Workers Assets
- repo-local `wasm-bindgen-cli` resolved from `Cargo.lock`

New applications built from the template should add their own authentication, authorization, rate limits, audit logging, and production data retention rules before handling real users.

## Secret Handling

No secrets are needed for the public static artifact. Use `.dev.vars` only for
optional local template work. Provider credentials and secret operations belong
to `cfctl` and the registered Cloudflare Authority. Both `.env` and `.dev.vars*`
are ignored. `.env.example` must remain placeholder-only.

## Release Security Gate

Before publication, run `./scripts/verify.sh`, export with
`bun scripts/export-pages.mjs`, and inspect the result in a local Pages preview.
See `RELEASE.md` for the separate provider gate. The existing source audit is:

```bash
cargo audit
rg -n --hidden --glob '!target/**' --glob '!build/**' --glob '!var/**' --glob '!.git/**' \
  --glob '!SECURITY.md' \
  '(sk_live_|sk_test_|AKIA|ghp_|github_pat_|ca30e922|CLOUDFLARE_API_TOKEN="[A-Za-z0-9_-]{20,}"|[0-9a-f]{32})' .
bash ./scripts/build-edge.sh
```
