#!/usr/bin/env bash
# Builds a release binary and assembles build/term-web.app.
# Usage: scripts/bundle.sh [--dev]
#   --dev  ad-hoc sign the bundle (hardened runtime) so it can be launched locally.
#          package.sh signs with Developer ID instead and does not pass --dev.
set -euo pipefail
source "$(dirname "$0")/common.sh"

DEV_SIGN=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --dev) DEV_SIGN=1; shift ;;
    -h|--help) sed -n '2,6p' "$0"; exit 0 ;;
    *) die "unknown argument: $1" ;;
  esac
done

"$ROOT/scripts/check-version-sync.sh"

log "Building release binary (arm64)"
cd "$ROOT"
swift build -c release --arch arm64 --product "$APP_NAME"
BIN_DIR="$(swift build -c release --arch arm64 --show-bin-path)"
[[ -x "$BIN_DIR/$APP_NAME" ]] || die "built binary not found at $BIN_DIR/$APP_NAME"

APP="$ROOT/build/$APP_NAME.app"
PLIST="$APP/Contents/Info.plist"
log "Assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/$APP_NAME" "$APP/Contents/MacOS/$APP_NAME"
cp "$ROOT/Packaging/Info.plist" "$PLIST"
plutil -replace CFBundleShortVersionString -string "$VERSION" "$PLIST"
plutil -replace CFBundleVersion -string "$VERSION" "$PLIST"
plutil -replace LSMinimumSystemVersion -string "$MIN_MACOS" "$PLIST"
plutil -replace CFBundleIdentifier -string "$BUNDLE_ID" "$PLIST"
plutil -lint "$PLIST" >/dev/null
cp "$ROOT/Packaging/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
printf 'APPL????' > "$APP/Contents/PkgInfo"
# Best effort: extended attributes break codesign. The sandbox's provenance
# attribute cannot be removed and is harmless to signing.
xattr -cr "$APP" 2>/dev/null || true

if [[ $DEV_SIGN -eq 1 ]]; then
  log "Ad-hoc signing (dev)"
  codesign --force --options runtime --sign - "$APP"
fi

log "Bundled $APP (version $VERSION)"
