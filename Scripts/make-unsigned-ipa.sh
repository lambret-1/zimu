#!/usr/bin/env bash
# 从未签名 .xcarchive 生成未签名 .ipa（Payload/SuperResApp.app）。
# 用法：make-unsigned-ipa.sh path/to/SuperResApp.xcarchive output.ipa
set -euo pipefail

if [ $# -ne 2 ]; then
  echo "Usage: $0 <path-to-xcarchive> <output-ipa>"
  exit 2
fi

ARCHIVE="$1"
OUTPUT_IPA="$2"
APP_NAME="SuperResApp"

if [ ! -d "$ARCHIVE" ]; then
  echo "::error::Archive not found: $ARCHIVE"
  exit 1
fi

APP_PATH="$ARCHIVE/Products/Applications/$APP_NAME.app"
if [ ! -d "$APP_PATH" ]; then
  echo "::error::App not found in archive: $APP_PATH"
  exit 1
fi

WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR"' EXIT

mkdir -p "$WORK_DIR/Payload"
cp -R "$APP_PATH" "$WORK_DIR/Payload/"
# 确保未签名产物不携带残留签名
rm -rf "$WORK_DIR/Payload/$APP_NAME.app/_CodeSignature"
rm -f  "$WORK_DIR/Payload/$APP_NAME.app/embedded.mobileprovision"

OUTPUT_DIR="$(dirname "$OUTPUT_IPA")"
mkdir -p "$OUTPUT_DIR"

( cd "$WORK_DIR" && zip -qry "$OLDPWD/$OUTPUT_IPA" Payload )

echo "Unsigned IPA created: $OUTPUT_IPA"
echo "Size: $(du -h "$OUTPUT_IPA" | cut -f1)"
