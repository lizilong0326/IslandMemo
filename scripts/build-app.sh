#!/bin/zsh
set -euo pipefail

ROOT_DIR="${0:A:h:h}"
# User-facing packages are emitted only when this script is explicitly run.
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$ROOT_DIR/Resources/Info.plist")"
APP_DIR="$ROOT_DIR/../../outputs/丫丫灵动-v${VERSION}.app"

cd "$ROOT_DIR"
mkdir -p "$ROOT_DIR/.cache/clang" "$ROOT_DIR/.cache/swiftpm" "$ROOT_DIR/.cache/config" "$ROOT_DIR/.cache/security"

SDK_PATH="/Library/Developer/CommandLineTools/SDKs/MacOSX26.sdk"
if [[ ! -d "$SDK_PATH" ]]; then
  SDK_PATH="$(xcrun --sdk macosx --show-sdk-path)"
fi

SDKROOT="$SDK_PATH" \
CLANG_MODULE_CACHE_PATH="$ROOT_DIR/.cache/clang" \
swift build -c release --disable-sandbox \
  --cache-path "$ROOT_DIR/.cache/swiftpm" \
  --config-path "$ROOT_DIR/.cache/config" \
  --security-path "$ROOT_DIR/.cache/security"

mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
cp ".build/release/IslandMemo" "$APP_DIR/Contents/MacOS/IslandMemo"
cp "$ROOT_DIR/Resources/Info.plist" "$APP_DIR/Contents/Info.plist"
cp "$ROOT_DIR/Resources/PkgInfo" "$APP_DIR/Contents/PkgInfo"
codesign --force --deep --sign - "$APP_DIR"

echo "$APP_DIR"
