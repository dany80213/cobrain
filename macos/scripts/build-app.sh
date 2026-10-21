#!/bin/bash
# Builds the Rust bridge, the Swift app, and wraps it into macos/build/Cobrain.app
set -euo pipefail
cd "$(dirname "$0")/.."
export PATH="/opt/homebrew/opt/rustup/bin:$HOME/.cargo/bin:$PATH"

(cd .. && cargo build --release -p cobrain-ffi)
swift build -c release

APP=build/Cobrain.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/Cobrain "$APP/Contents/MacOS/Cobrain"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp ../assets/app-icon/wordcraft.icns "$APP/Contents/Resources/Cobrain.icns" # placeholder icon until Cobrain has its own
codesign --force --sign - "$APP" >/dev/null
echo "Built $APP"
