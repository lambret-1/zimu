#!/usr/bin/env bash
# 校验第三方许可文件存在并出现在关于页资源中。
set -euo pipefail

LICENSES_DIR="Resources/Licenses"
REQUIRED=("OpenCV-LICENSE.txt")

for f in "${REQUIRED[@]}"; do
  if [ ! -f "$LICENSES_DIR/$f" ]; then
    echo "::error::Missing license file: $LICENSES_DIR/$f"
    exit 1
  fi
done

if ! grep -rq "OpenCV" Features/Settings 2>/dev/null; then
  echo "::warning::About page may not reference OpenCV license."
fi

echo "License check OK."
