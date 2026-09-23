#!/usr/bin/env bash
# Builds, signs and verifies dist/term-web-<VERSION>.pkg.
# Usage: scripts/package.sh [--notary-profile NAME] [--force]
#   --notary-profile NAME  notarize and staple with this notarytool keychain
#                          profile (or set NOTARY_PROFILE). Without it nothing
#                          is sent to Apple.
#   --force                replace an existing dist/term-web-<VERSION>.pkg.
# Identities can be overridden with APP_SIGN_ID and INSTALLER_SIGN_ID
# (a SHA-1 hash or the full certificate name).
set -euo pipefail
source "$(dirname "$0")/common.sh"

NOTARY_PROFILE="${NOTARY_PROFILE:-}"
FORCE=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --notary-profile) NOTARY_PROFILE="${2:?--notary-profile needs a profile name}"; shift 2 ;;
    --force) FORCE=1; shift ;;
    -h|--help) sed -n '2,10p' "$0"; exit 0 ;;
    *) die "unknown argument: $1" ;;
  esac
done

# Developer ID Application: MLNavigator Inc. (4JB58L7BTZ)
APP_SIGN_ID="${APP_SIGN_ID:-092DB0E5D9AC568FD4CD8D2C1D55A4EA0C09E71E}"
# Developer ID Installer: MLNavigator Inc. (4JB58L7BTZ)
INSTALLER_SIGN_ID="${INSTALLER_SIGN_ID:-D8CC67B106AC29F11A447991A0A659B5632D3CE4}"

APP="$ROOT/build/$APP_NAME.app"
COMPONENT="$ROOT/build/$APP_NAME-component.pkg"
PKG="$ROOT/dist/$APP_NAME-$VERSION.pkg"

if [[ -e "$PKG" ]]; then
  [[ $FORCE -eq 1 ]] || die "$PKG exists (bump VERSION, remove it, or pass --force)"
  rm -f "$PKG" "$PKG.sha256"
fi

# 1. Release build and bundle.
"$ROOT/scripts/bundle.sh"

# 2. Sign the app: hardened runtime, secure timestamp, no entitlements, no --deep.
log "Signing app with Developer ID Application"
codesign --force --options runtime --timestamp --sign "$APP_SIGN_ID" "$APP"
codesign --verify --deep --strict --verbose=2 "$APP"
SIGN_INFO="$(codesign -dvv "$APP" 2>&1)"
grep -q 'flags=0x10000(runtime)' <<<"$SIGN_INFO" || die "hardened runtime flag missing"
grep -q "TeamIdentifier=$TEAM_ID" <<<"$SIGN_INFO" || die "TeamIdentifier is not $TEAM_ID"
grep -q '^Timestamp=' <<<"$SIGN_INFO" || die "secure timestamp missing"
[[ -z "$(codesign -d --entitlements - --xml "$APP" 2>/dev/null)" ]] || die "unexpected entitlements"

# 3. Component package that installs term-web.app into /Applications.
log "Building component package"
STAGE="$ROOT/build/pkgroot"
rm -rf "$STAGE" "$COMPONENT"
mkdir -p "$STAGE"
ditto "$APP" "$STAGE/$APP_NAME.app"
pkgbuild --analyze --root "$STAGE" "$ROOT/build/component.plist"
plutil -replace 0.BundleIsRelocatable -bool NO "$ROOT/build/component.plist"
pkgbuild --root "$STAGE" --component-plist "$ROOT/build/component.plist" \
  --identifier "$PKG_ID" --version "$VERSION" \
  --install-location /Applications "$COMPONENT"

# 4. Product archive with the distribution file, signed with Developer ID Installer.
log "Building signed product archive"
sed -e "s/@VERSION@/$VERSION/g" -e "s/@MIN_MACOS@/$MIN_MACOS/g" \
  "$ROOT/Packaging/distribution.xml" > "$ROOT/build/distribution.xml"
mkdir -p "$ROOT/dist"
productbuild --distribution "$ROOT/build/distribution.xml" --package-path "$ROOT/build" \
  --sign "$INSTALLER_SIGN_ID" --timestamp "$PKG"

# 5. Checks. All are hard failures except spctl, which rejects until notarized.
log "Verifying package"
pkgutil --check-signature "$PKG"
pkgutil --payload-files "$PKG" | grep -qx "./$APP_NAME.app/Contents/MacOS/$APP_NAME" \
  || die "payload lacks ./$APP_NAME.app/Contents/MacOS/$APP_NAME"
rm -rf "$ROOT/build/expanded" "$ROOT/build/full"
pkgutil --expand "$PKG" "$ROOT/build/expanded"
grep -q 'install-location="/Applications"' "$ROOT/build/expanded/$APP_NAME-component.pkg/PackageInfo" \
  || die "component install-location is not /Applications"
grep -q 'hostArchitectures="arm64"' "$ROOT/build/expanded/Distribution" \
  || die "distribution lacks the arm64 host requirement"
pkgutil --expand-full "$PKG" "$ROOT/build/full"
codesign --verify --deep --strict --verbose=2 "$ROOT/build/full/$APP_NAME-component.pkg/Payload/$APP_NAME.app"
log "Payload installs to /Applications/$APP_NAME.app"
if pkgutil --payload-files "$PKG" | grep -q '/\._'; then
  warn "AppleDouble ._ entries are in the payload (provenance xattrs, e.g. from a sandboxed shell)."
  warn "They are harmless to the signature; rebuild from a normal terminal for a clean release."
fi

set +e
spctl --assess --type execute -vv "$APP"; app_status=$?
spctl --assess --type install -vv "$PKG"; pkg_status=$?
set -e
echo "spctl app exit: $app_status, spctl pkg exit: $pkg_status"
if [[ $app_status -ne 0 || $pkg_status -ne 0 ]]; then
  echo "Gatekeeper rejects un-notarized Developer ID software (source=Unnotarized Developer ID); expected before notarization."
fi

# 6. Optional notarization, only with an explicit keychain profile.
if [[ -n "$NOTARY_PROFILE" ]]; then
  log "Notarizing with keychain profile '$NOTARY_PROFILE'"
  xcrun notarytool submit "$PKG" --keychain-profile "$NOTARY_PROFILE" --wait --timeout 30m
  xcrun stapler staple "$PKG"
  xcrun stapler validate "$PKG"
  spctl --assess --type install -vv "$PKG"
else
  cat <<EOF
Notarization skipped (no --notary-profile). To notarize:
  1. Store credentials once (Apple ID + app-specific password, or an App Store Connect API key):
       xcrun notarytool store-credentials <profile> --apple-id <apple-id> --team-id $TEAM_ID
       xcrun notarytool store-credentials <profile> --key <AuthKey.p8> --key-id <id> --issuer <uuid>
  2. Rebuild and notarize:
       scripts/package.sh --force --notary-profile <profile>
EOF
fi

(cd "$ROOT/dist" && shasum -a 256 "$(basename "$PKG")" | tee "$(basename "$PKG").sha256")
log "Built $PKG"
