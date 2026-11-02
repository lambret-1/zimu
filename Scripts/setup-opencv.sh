#!/usr/bin/env bash
# 校验 OpenCV XCFramework 是否就位。不下载网络资源，符合“纯端侧/可审计”原则。
set -euo pipefail

OPENCV_XCFRAMEWORK_DIR="Frameworks/opencv2.xcframework"

if [ ! -d "$OPENCV_XCFRAMEWORK_DIR" ]; then
  echo "::error::OpenCV XCFramework not found at $OPENCV_XCFRAMEWORK_DIR"
  echo "请将裁剪版 opencv2.xcframework 放入 Frameworks/ 并通过 Git LFS 提交。"
  exit 1
fi

for slice in ios-arm64 ios-arm64_x86_64-simulator; do
  if [ ! -d "$OPENCV_XCFRAMEWORK_DIR/$slice/opencv2.framework" ]; then
    echo "::error::Missing slice $slice in $OPENCV_XCFRAMEWORK_DIR"
    exit 1
  fi
done

MODULES="$OPENCV_XCFRAMEWORK_DIR/ios-arm64/opencv2.framework/Headers/opencv2/opencv_modules.hpp"
if [ -f "$MODULES" ]; then
  for m in HAVE_OPENCV_CORE HAVE_OPENCV_IMGPROC HAVE_OPENCV_PHOTO; do
    if ! grep -q "#define $m" "$MODULES"; then
      echo "::warning::$m not defined — 确认裁剪模块是否符合方案（core/imgproc/photo）"
    fi
  done
fi

echo "OpenCV XCFramework OK."
