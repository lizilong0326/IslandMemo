#!/bin/zsh
set -euo pipefail
ROOT_DIR="${0:A:h:h}"
cd "$ROOT_DIR"
QA_DIR="$ROOT_DIR/.build/memo-floating-validation"
mkdir -p "$QA_DIR"
swiftc -parse-as-library -swift-version 6 -target "$(uname -m)-apple-macos13.0" \
  Sources/IslandMemo/TaskItem.swift Sources/IslandMemo/TaskRepository.swift \
  Sources/IslandMemo/WindowInteractionPolicy.swift \
  Sources/IslandMemo/TaskStore.swift Sources/IslandMemo/AppSettingsStore.swift \
  Sources/IslandMemo/ShortcutSettings.swift Sources/IslandMemo/HomeLayoutEngine.swift \
  Sources/IslandMemo/MemoCategoryLayoutEngine.swift Sources/IslandMemo/IslandTheme.swift \
  Sources/IslandMemo/MemoTaskPickers.swift Sources/IslandMemo/MemoWorkspaceView.swift \
  Sources/IslandMemo/MemoFloatingView.swift Sources/IslandMemo/MemoFloatingController.swift \
  Tests/MemoFloating/MemoFloatingValidation.swift -o "$QA_DIR/MemoFloatingValidation"
python3 - "$QA_DIR/MemoFloatingValidation" <<'PY'
import subprocess, sys
try:
    result = subprocess.run([sys.argv[1]], timeout=45)
except subprocess.TimeoutExpired:
    sys.exit("FAIL: memo floating validation stalled for 45 seconds")
sys.exit(result.returncode)
PY
