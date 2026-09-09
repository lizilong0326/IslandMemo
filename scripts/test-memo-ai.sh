#!/bin/zsh
set -euo pipefail
ROOT_DIR="${0:A:h:h}"
cd "$ROOT_DIR"
QA_DIR="$ROOT_DIR/.build/memo-ai-validation"
APP_DIR="$QA_DIR/MemoAIValidation.app"
mkdir -p "$APP_DIR/Contents/MacOS"
PORT_FILE="$(mktemp)"
python3 Tests/MemoAI/mock_server.py "$PORT_FILE" &
MOCK_PID=$!
trap 'kill "$MOCK_PID" 2>/dev/null || true; rm -f "$PORT_FILE"' EXIT
for attempt in {1..50}; do
    [[ -s "$PORT_FILE" ]] && break
    sleep 0.1
done
cat > "$APP_DIR/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>com.islandmemo.memo-ai-validation</string>
<key>CFBundleExecutable</key><string>MemoAIValidation</string>
<key>CFBundleName</key><string>MemoAIValidation</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>LSUIElement</key><true/>
</dict></plist>
PLIST
swiftc -parse-as-library -swift-version 6 -target "$(uname -m)-apple-macos13.0" \
  Sources/IslandMemo/MemoAIService.swift \
  Sources/IslandMemo/MemoAICredentialStore.swift \
  Sources/IslandMemo/TaskItem.swift Sources/IslandMemo/TaskRepository.swift \
  Sources/IslandMemo/TaskStore.swift Sources/IslandMemo/MemoCaptureController.swift \
  Sources/IslandMemo/AppSettingsStore.swift Sources/IslandMemo/ShortcutSettings.swift \
  Sources/IslandMemo/HomeLayoutEngine.swift Sources/IslandMemo/MemoCategoryLayoutEngine.swift \
  Sources/IslandMemo/MemoAISettingsView.swift \
  Sources/IslandMemo/ApplicationMenus.swift \
  Sources/IslandMemo/MemoTaskPickers.swift Sources/IslandMemo/IslandTheme.swift \
  Tests/MemoAI/MemoAICredentialValidation.swift Tests/MemoAI/MemoAIValidation.swift -o "$APP_DIR/Contents/MacOS/MemoAIValidation"
"$APP_DIR/Contents/MacOS/MemoAIValidation" "$(cat "$PORT_FILE")" "$QA_DIR" "$@"
