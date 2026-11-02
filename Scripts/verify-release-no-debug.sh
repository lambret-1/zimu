#!/usr/bin/env bash
# 校验 Release 构建产物/源码不含调试入口与敏感日志导出。
# 用法：
#   verify-release-no-debug.sh --source-only
#   verify-release-no-debug.sh --archive path/to/SuperResApp.xcarchive
set -euo pipefail

MODE=""
ARCHIVE_PATH=""
while [ $# -gt 0 ]; do
  case "$1" in
    --source-only) MODE="source"; shift ;;
    --archive)     MODE="archive"; ARCHIVE_PATH="$2"; shift 2 ;;
    *) echo "Unknown arg: $1"; exit 2 ;;
  esac
done

# 1) 源码层：Debug/ 文件必须 #if DEBUG 包裹
while IFS= read -r f; do
  if ! grep -q "#if DEBUG" "$f"; then
    echo "::error file=$f::Debug file missing #if DEBUG"
    exit 1
  fi
done < <(find Debug -type f -name '*.swift')

# 2) 源码层：DebugPanelView 入口必须在 #if DEBUG 内
if grep -rn "DebugPanelView(" --include='*.swift' Features/ | grep -v "#if DEBUG" >/dev/null 2>&1; then
  echo "::error::DebugPanelView entry outside #if DEBUG"
  exit 1
fi

echo "Source-level debug isolation OK."

if [ "$MODE" = "archive" ]; then
  if [ ! -d "$ARCHIVE_PATH" ]; then
    echo "::error::Archive not found: $ARCHIVE_PATH"
    exit 1
  fi
  APP_PATH="$ARCHIVE_PATH/Products/Applications/SuperResApp.app"
  BIN="$APP_PATH/SuperResApp"
  if [ ! -f "$BIN" ]; then
    echo "::error::Binary not found: $BIN"
    exit 1
  fi
  if strings "$BIN" | grep -qE "DebugPanelView|DebugOverlayView|DebugReportExporter"; then
    echo "::error::Release binary contains debug symbols/strings"
    exit 1
  fi
  echo "Archive binary debug-string scan passed."
fi

echo "Release safety checks passed."
