#!/bin/bash
set -euo pipefail
project_root="$(cd "$(dirname "$0")/.." && pwd)"
check_root="$(mktemp -d /private/tmp/personal-dashboard-tracking-checks.XXXXXX)"
trap 'rm -rf "$check_root"' EXIT
if [[ -z "${DEVELOPER_DIR:-}" && -d /Applications/Xcode.app/Contents/Developer ]]; then
    export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi
cd "$project_root"
xcrun swiftc -module-cache-path "$check_root/modules" \
    PersonalDashboard/Models.swift PersonalDashboard/ScreenTimeTracker.swift Tests/TrackingChecks.swift \
    -o "$check_root/TrackingChecks"
TZ=America/New_York "$check_root/TrackingChecks"
