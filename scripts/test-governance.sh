#!/bin/zsh
set -euo pipefail
ROOT_DIR="${0:A:h:h}"
cd "$ROOT_DIR"
QA_DIR="$ROOT_DIR/.build/governance-validation"
APP_DIR="$QA_DIR/GovernanceValidation.app"
mkdir -p "$APP_DIR/Contents/MacOS"
cat > "$APP_DIR/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>com.islandmemo.governance-validation</string>
<key>CFBundleExecutable</key><string>GovernanceValidation</string>
<key>CFBundleName</key><string>GovernanceValidation</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>LSUIElement</key><true/>
</dict></plist>
PLIST
swiftc -parse-as-library -swift-version 6 -target "$(uname -m)-apple-macos13.0" \
  Sources/IslandMemo/TaskItem.swift Sources/IslandMemo/TaskRepository.swift \
  Sources/IslandMemo/TaskStore.swift Sources/IslandMemo/AppSettingsStore.swift \
  Sources/IslandMemo/ShortcutSettings.swift Sources/IslandMemo/HomeLayoutEngine.swift \
  Sources/IslandMemo/KeychainHelper.swift Sources/IslandMemo/RecordingStore.swift \
  Sources/IslandMemo/OrderedFileWriter.swift Sources/IslandMemo/CommandsStore.swift \
  Sources/IslandMemo/WindowInteractionPolicy.swift Sources/IslandMemo/ClipboardEntry.swift \
  Sources/IslandMemo/ClipboardStore.swift Sources/IslandMemo/NotifyServer.swift \
  Sources/IslandMemo/CodexStatusStore.swift Sources/IslandMemo/CodexStatusClient.swift \
  Sources/IslandMemo/CodexStatusModels.swift Sources/IslandMemo/CodexTaskRuntimeIndex.swift -lsqlite3 \
  Tests/Governance/GovernanceValidation.swift -o "$APP_DIR/Contents/MacOS/GovernanceValidation"
python3 - "$APP_DIR/Contents/MacOS/GovernanceValidation" <<'PY'
import subprocess, sys
try:
    result = subprocess.run([sys.argv[1]], timeout=45)
except subprocess.TimeoutExpired:
    sys.exit("FAIL: governance validation stalled for 45 seconds")
sys.exit(result.returncode)
PY
