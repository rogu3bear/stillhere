# Contributing

This is the term-web product website, adopted from `leptos-cf`. The public
guide is implemented in `src/components/docs_*.rs`; `docs/` retains developer
recipes from the template. Product changes should reflect current native
behavior and preserve the monochrome design and real screenshot provenance.

## Development Setup

```bash
rustup toolchain install stable
rustup target add wasm32-unknown-unknown
./scripts/bootstrap.sh
```

## Expected Checks

Run the full release readiness verification before opening a pull request:

```bash
./scripts/verify.sh
```

This is the authoritative local release gate. For quick iteration on small changes you can use the lighter protocol described in `docs/agent-playbook.md`.

`wrangler.toml` retains the template's placeholder D1 IDs for local qualification.
The product site does not use D1. Public hosting uses a static Pages export
of the Leptos-rendered pages; do not provision placeholder bindings.
Provider operations go through `cfctl` and the registered Cloudflare Authority.

## Change Boundaries

- Keep generated output out of git.
- Keep docs and verification scripts aligned with runtime behavior.
- Prefer small, explicit examples over hidden magic.
- Do not add real service IDs, tokens, or personal environment values to examples.
- If you add a new Cloudflare binding, document the binding, local setup, deploy proof, and failure mode.

## Realtime Features

Read `docs/realtime.md` before adding WebSocket behavior. Request-scoped capability checks may stay in the Worker. Shared state, rooms, collaboration, presence, fanout, and reconnect state should use Durable Objects.
