#!/usr/bin/env bash
# Fails if the minimum macOS differs between Package.swift, common.sh,
# Packaging/Info.plist and Packaging/distribution.xml.
set -euo pipefail
source "$(dirname "$0")/common.sh"

major="${MIN_MACOS%%.*}"
status=0

grep -q "\.macOS(\.v${major})" "$ROOT/Package.swift" \
  || { warn "Package.swift platform is not .macOS(.v${major})"; status=1; }

plist_min="$(plutil -extract LSMinimumSystemVersion raw -o - "$ROOT/Packaging/Info.plist")"
[[ "$plist_min" == "$MIN_MACOS" ]] \
  || { warn "Packaging/Info.plist LSMinimumSystemVersion is $plist_min, expected $MIN_MACOS"; status=1; }

grep -q 'os-version min="@MIN_MACOS@"' "$ROOT/Packaging/distribution.xml" \
  || { warn "Packaging/distribution.xml must use os-version min=\"@MIN_MACOS@\""; status=1; }

grep -q 'hostArchitectures="arm64"' "$ROOT/Packaging/distribution.xml" \
  || { warn "Packaging/distribution.xml must require hostArchitectures=\"arm64\""; status=1; }

[[ $status -eq 0 ]] || die "minimum macOS settings are out of sync"
log "Version sync OK (VERSION $VERSION, macOS $MIN_MACOS)"
