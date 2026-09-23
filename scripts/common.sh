# Shared settings for the build scripts. Source it; do not run it.
# Sets ROOT, VERSION, MIN_MACOS, BUNDLE_ID, APP_NAME, APP_EXECUTABLE, CLI_NAME and the log helpers.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="term-web"
# The menu bar app's binary (CFBundleExecutable) and the CLI shipped next to it.
APP_EXECUTABLE="TermWeb"
CLI_NAME="term-web"
BUNDLE_ID="com.mlnavigator.term-web"
PKG_ID="com.mlnavigator.term-web.pkg"
TEAM_ID="4JB58L7BTZ"
# Keep in sync with Package.swift (.macOS(.v26)); check-version-sync.sh enforces it.
MIN_MACOS="26.0"

log()  { printf '==> %s\n' "$*"; }
warn() { printf 'WARN: %s\n' "$*" >&2; }
die()  { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

[[ -f "$ROOT/VERSION" ]] || die "missing $ROOT/VERSION"
VERSION="$(tr -d '[:space:]' < "$ROOT/VERSION")"
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "VERSION must be MAJOR.MINOR.PATCH, got '$VERSION'"
