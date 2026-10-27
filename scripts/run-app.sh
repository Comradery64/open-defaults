#!/bin/zsh
DD="${1:-build/dd-local}"
pkill -x DefaultApps || true
open -n "$DD/Build/Products/Debug/DefaultApps.app"
for i in {1..20}; do
  pgrep -x DefaultApps && exit 0
  sleep 0.5
done
echo "app did not start"
exit 1
