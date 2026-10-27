#!/bin/bash
# Builds Cobrain for a real iPad. Needs a development team: DEVELOPMENT_TEAM=XXXXXXXXXX ios/scripts/build-device.sh
set -euo pipefail
cd "$(dirname "$0")/.."
export PATH="/opt/homebrew/opt/rustup/bin:$HOME/.cargo/bin:$PATH"
(cd .. && cargo build --release -p cobrain-ffi --target aarch64-apple-ios)
VERSION="$(tr -d '[:space:]' < ../VERSION)"
BUILD="$(git rev-list --count HEAD 2>/dev/null || echo 1)"
xcodegen generate --quiet
xcodebuild -project Cobrain.xcodeproj -scheme Cobrain -sdk iphoneos -destination "generic/platform=iOS" -derivedDataPath build \
  DEVELOPMENT_TEAM="${DEVELOPMENT_TEAM:?set DEVELOPMENT_TEAM}" MARKETING_VERSION="$VERSION" CURRENT_PROJECT_VERSION="$BUILD" -allowProvisioningUpdates build | grep -E "error:|BUILD"
echo "build/Build/Products/Debug-iphoneos/Cobrain.app"
