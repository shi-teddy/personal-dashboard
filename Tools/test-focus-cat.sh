#!/bin/bash
set -euo pipefail
project_root="$(cd "$(dirname "$0")/.." && pwd)"
check_root="$(mktemp -d /private/tmp/approved-cat-checks.XXXXXX)"
if [[ -z "${DEVELOPER_DIR:-}" && -d /Applications/Xcode.app/Contents/Developer ]]; then
    export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi
cd "$project_root"
xcodebuild -project PersonalDashboard.xcodeproj -scheme PersonalDashboard -configuration Release \
    -derivedDataPath "$check_root/build" CODE_SIGNING_ALLOWED=NO build > "$check_root/build.log" 2>&1
check_app="$check_root/ApprovedCatChecks.app/Contents"
mkdir -p "$check_app/MacOS" "$check_app/Resources"
cp "$check_root/build/Build/Products/Release/PersonalDashboard.app/Contents/Resources/ApprovedCatAnimation.json" "$check_app/Resources/"
xcrun swiftc -module-cache-path "$check_root/modules" \
    PersonalDashboard/FocusCatArtwork.swift PersonalDashboard/FocusCatView.swift \
    PersonalDashboard/FocusCatController.swift Tests/FocusCatChecks.swift \
    -o "$check_app/MacOS/ApprovedCatChecks"
"$check_app/MacOS/ApprovedCatChecks" "$project_root/output/approved-cat-integration" "$@"
echo "Release build and animation checks passed. Build log: $check_root/build.log"
