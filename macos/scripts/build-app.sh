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
cp -R Resources/icons "$APP/Contents/Resources/icons"
cp Resources/Info.plist "$APP/Contents/Info.plist"
# Where this build comes from, for Cobrain > Check for Updates (the app compares it with GitHub's main).
ROOT="$(cd .. && pwd)"
COMMIT="$(git -C "$ROOT" rev-parse HEAD 2>/dev/null || true)"
BRANCH="$(git -C "$ROOT" rev-parse --abbrev-ref HEAD 2>/dev/null || true)"
# Version: the VERSION file at the repo root (see scripts/release.sh); the build number is the commit count.
VERSION="$(tr -d '[:space:]' < "$ROOT/VERSION" 2>/dev/null || echo 1.0.0)"
BUILD="$(git -C "$ROOT" rev-list --count HEAD 2>/dev/null || echo 1)"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" -c "Set :CFBundleVersion $BUILD" "$APP/Contents/Info.plist"
for kv in "CobrainSourceDir:$ROOT" "CobrainCommit:$COMMIT" "CobrainBranch:$BRANCH"; do
  /usr/libexec/PlistBuddy -c "Add :${kv%%:*} string ${kv#*:}" "$APP/Contents/Info.plist" >/dev/null
done
cp ../assets/app-icon/wordcraft.icns "$APP/Contents/Resources/Cobrain.icns" # placeholder icon until Cobrain has its own
codesign --force --sign - "$APP" >/dev/null
echo "Built $APP"
