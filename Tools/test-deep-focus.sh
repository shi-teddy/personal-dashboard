#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="${TMPDIR:-/tmp}/personal-dashboard-deep-focus-tests"
mkdir -p "$BUILD_DIR"

DEVELOPER_DIR=/Library/Developer/CommandLineTools xcrun swiftc \
  -module-cache-path "$BUILD_DIR/module-cache" \
  "$ROOT/PersonalDashboard/Models.swift" \
  "$ROOT/Tools/DeepFocusChecks.swift" \
  -o "$BUILD_DIR/deep-focus-checks"

"$BUILD_DIR/deep-focus-checks"
