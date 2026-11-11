#!/bin/bash
# Runs the unit tests. With only the Command Line Tools installed, SwiftPM does not pass the
# Swift Testing macro plugin and framework paths, so they are supplied here when present.
set -euo pipefail
cd "$(dirname "$0")/.."
CLT="/Library/Developer/CommandLineTools"
FLAGS=()
if [[ "$(xcode-select -p)" == "$CLT" && -d "$CLT/usr/lib/swift/host/plugins/testing" ]]; then
  FLAGS=(-Xswiftc -plugin-path -Xswiftc "$CLT/usr/lib/swift/host/plugins/testing"
         -Xswiftc -F -Xswiftc "$CLT/Library/Developer/Frameworks"
         -Xlinker -rpath -Xlinker "$CLT/Library/Developer/Frameworks")
fi
swift test "${FLAGS[@]}" "$@"
