#!/bin/zsh
set -euo pipefail
ROOT_DIR="${0:A:h:h}"
cd "$ROOT_DIR"
QA_DIR="$ROOT_DIR/.build/settings-ui-validation"
APP_DIR="$QA_DIR/SettingsUIValidation.app"
mkdir -p "$APP_DIR/Contents/MacOS"
swift build
BUILD_DIR="$(swift build --show-bin-path)"
cat > "$APP_DIR/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>com.islandmemo.settings-ui-validation</string>
<key>CFBundleExecutable</key><string>SettingsUIValidation</string>
<key>CFBundleName</key><string>SettingsUIValidation</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>LSUIElement</key><true/>
</dict></plist>
PLIST
SWIFT_SOURCES=()
for source in Sources/IslandMemo/*.swift; do
  if [[ "${source:t}" != main.swift && "${source:t}" != AppDelegate.swift ]]; then SWIFT_SOURCES+=("$source"); fi
done
swiftc -parse-as-library -swift-version 6 -target "$(uname -m)-apple-macos13.0" \
  -I "$BUILD_DIR/Modules" -lsqlite3 "${SWIFT_SOURCES[@]}" \
  "$BUILD_DIR"/LunarSwift.build/*.swift.o Tests/Governance/SettingsUIValidation.swift \
  -o "$APP_DIR/Contents/MacOS/SettingsUIValidation"
python3 - "$APP_DIR/Contents/MacOS/SettingsUIValidation" "$@" <<'PY'
import subprocess, sys
try:
    result = subprocess.run(sys.argv[1:], timeout=60)
except subprocess.TimeoutExpired:
    sys.exit("FAIL: settings UI render stalled for 45 seconds")
sys.exit(result.returncode)
PY
