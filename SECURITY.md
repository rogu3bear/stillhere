# Security policy

Still Here is preparing its first public version, v0.1.0. A source release and
a signed, notarized installer are qualified separately.

## Report a vulnerability

Use the repository's private vulnerability reporting feature if available, or
contact the maintainer privately through their GitHub profile:
https://github.com/rogu3bear. Do not include secrets or exploit details in a
public issue. Include the version, reproduction steps, observed behavior, and
what boundary you believe was crossed.

## Boundaries

The native app observes local processes owned by the current user. It reads a
small allowlist of agent environment markers and makes HTTP(S) requests only to
detected loopback servers. It has no account, telemetry, or hosted MCP service.
Stop checks process identity before signaling; hidden processes do not become
safe to stop merely by showing them. The MCP interface has its own caller and
ownership checks, described in the user guide.

The public website is a static Pages export with no forms, database, production
secrets, or session cookies. See [website/SECURITY.md](website/SECURITY.md) for
its CSP, asset, and deployment boundaries.

Never commit credentials, private keys, real process environment dumps, or
screenshots containing private projects. Release signing and provider
credentials stay outside the source repository.
