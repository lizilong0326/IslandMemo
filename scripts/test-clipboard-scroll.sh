#!/bin/zsh
set -euo pipefail
ROOT_DIR="${0:A:h:h}"
cd "$ROOT_DIR"
QA_DIR="$ROOT_DIR/.build/clipboard-scroll-validation"
APP_DIR="$QA_DIR/ClipboardScrollValidation.app"
mkdir -p "$APP_DIR/Contents/MacOS"
cat > "$APP_DIR/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>com.islandmemo.clipboard-scroll-validation</string>
<key>CFBundleExecutable</key><string>ClipboardScrollValidation</string>
<key>CFBundleName</key><string>ClipboardScrollValidation</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>LSUIElement</key><true/>
</dict></plist>
PLIST
swiftc -parse-as-library -swift-version 6 -target "$(uname -m)-apple-macos13.0" \
  Sources/IslandMemo/ClipboardEntry.swift Sources/IslandMemo/ClipboardStore.swift \
  Sources/IslandMemo/ClipboardHistoryView.swift Sources/IslandMemo/AppSettingsStore.swift \
  Sources/IslandMemo/TaskItem.swift \
  Sources/IslandMemo/ShortcutSettings.swift Sources/IslandMemo/HomeLayoutEngine.swift \
  Sources/IslandMemo/MemoCategoryLayoutEngine.swift \
  Tests/Clipboard/ClipboardScrollValidation.swift -o "$APP_DIR/Contents/MacOS/ClipboardScrollValidation"
# A layout loop blocks the main run loop, so enforce the deadline out of process.
python3 - "$APP_DIR/Contents/MacOS/ClipboardScrollValidation" <<'PY'
import subprocess, sys
try:
    result = subprocess.run([sys.argv[1]], timeout=45)
except subprocess.TimeoutExpired:
    sys.exit("FAIL: clipboard scrolling stalled for 45 seconds")
sys.exit(result.returncode)
PY
