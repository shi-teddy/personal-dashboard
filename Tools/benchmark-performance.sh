#!/bin/bash
set -euo pipefail
project_root="$(cd "$(dirname "$0")/.." && pwd)"
probe_root="$(mktemp -d /private/tmp/dashboard-performance.XXXXXX)"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
cd "$project_root"
mkdir -p "$probe_root/PerformanceProbe.app/Contents/MacOS" "$probe_root/PerformanceProbe.app/Contents/Resources"
cp PersonalDashboard/Resources/ApprovedCatAnimation.json "$probe_root/PerformanceProbe.app/Contents/Resources/"
xcrun swiftc PersonalDashboard/BrowserScriptRunner.swift -O -module-cache-path "$probe_root/modules" PersonalDashboard/Models.swift \
    PersonalDashboard/FocusCatArtwork.swift PersonalDashboard/FocusCatView.swift PersonalDashboard/FocusCatController.swift \
    PersonalDashboard/ScreenTimeTracker.swift Tests/PerformanceProbe.swift \
    -o "$probe_root/PerformanceProbe.app/Contents/MacOS/PerformanceProbe"
/usr/bin/time -l "$probe_root/PerformanceProbe.app/Contents/MacOS/PerformanceProbe"
