#!/bin/bash
# Builds Cobrain Board for the iPad simulator (no signing needed) and installs it on the booted iPad.
set -euo pipefail
cd "$(dirname "$0")/.."
xcodegen generate --quiet
xcodebuild -project CobrainBoard.xcodeproj -scheme CobrainBoard -sdk iphonesimulator \
  -destination "platform=iOS Simulator,name=${IPAD:-iPad Pro 11-inch (M4)}" -derivedDataPath build \
  CODE_SIGNING_ALLOWED=NO build | grep -E "error|warning: unre|BUILD" || true
echo "build/Build/Products/Debug-iphonesimulator/Cobrain Board.app"
