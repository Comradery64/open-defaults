#!/bin/zsh
set -euo pipefail
DD="${1:-build/dd-local}"
set +e
xcodebuild -project DefaultApps.xcodeproj -scheme DefaultApps -configuration Debug -derivedDataPath "$DD" build 2>&1 | tail -n 40
rc=${pipestatus[1]}
set -e
if (( rc != 0 )); then exit $rc; fi
echo "APP=$DD/Build/Products/Debug/DefaultApps.app"
