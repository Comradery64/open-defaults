#!/bin/zsh
set -euo pipefail
DD="${1:-build/dd-local}"
set +e
xcodebuild -project DefaultApps.xcodeproj -scheme DefaultApps -configuration Debug -derivedDataPath "$DD" test -destination 'platform=macOS' 2>&1 | tail -n 40
rc=${pipestatus[1]}
set -e
exit $rc
