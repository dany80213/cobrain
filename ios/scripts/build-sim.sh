#!/bin/bash
# Builds the Rust engine for the iOS simulator, then Cobrain for the iPad simulator (no signing needed).
set -euo pipefail
cd "$(dirname "$0")/.."
export PATH="/opt/homebrew/opt/rustup/bin:$HOME/.cargo/bin:$PATH"
(cd .. && cargo build --release -p cobrain-ffi --target aarch64-apple-ios-sim)
VERSION="$(tr -d '[:space:]' < ../VERSION)"
BUILD="$(git rev-list --count HEAD 2>/dev/null || echo 1)"
xcodegen generate --quiet
xcodebuild -project Cobrain.xcodeproj -scheme Cobrain -sdk iphonesimulator \
  -destination "platform=iOS Simulator,name=${IPAD:-iPad Pro 11-inch (M4)}" -derivedDataPath build \
  MARKETING_VERSION="$VERSION" CURRENT_PROJECT_VERSION="$BUILD" CODE_SIGNING_ALLOWED=NO build | grep -E "error:|BUILD" || true
echo "build/Build/Products/Debug-iphonesimulator/Cobrain.app"
