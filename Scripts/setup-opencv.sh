#!/usr/bin/env bash
# Fetch pinned opencv-mobile v37 device/simulator binaries and assemble an XCFramework.
set -euo pipefail

VERSION="2.4.13.7"
RELEASE_TAG="v37"
BASE_URL="https://github.com/nihui/opencv-mobile/releases/download/${RELEASE_TAG}"
DEVICE_ZIP="opencv-mobile-${VERSION}-ios.zip"
SIMULATOR_ZIP="opencv-mobile-${VERSION}-ios-simulator.zip"
DEVICE_SHA256="9ad02088639a4dbd73039ca10d2d5157d028bcb4c71cefe8cf17900f398fcc0f"
SIMULATOR_SHA256="32d6b3d6196b743b2ba5383f6cb53fbbd6297e83ccd8052eefbb986b0684164e"

FRAMEWORKS_DIR="Frameworks"
OUTPUT_DIR="${FRAMEWORKS_DIR}/opencv2.xcframework"
WORK_DIR="${FRAMEWORKS_DIR}/.opencv-download"

if [ -d "$OUTPUT_DIR" ] && [ -d "$OUTPUT_DIR/ios-arm64/opencv2.framework" ] && [ -d "$OUTPUT_DIR/ios-arm64_x86_64-simulator/opencv2.framework" ]; then
  echo "OpenCV XCFramework already exists."
  exit 0
fi

command -v curl >/dev/null
command -v unzip >/dev/null
command -v xcodebuild >/dev/null
command -v shasum >/dev/null

rm -rf "$WORK_DIR" "$OUTPUT_DIR"
mkdir -p "$WORK_DIR/device" "$WORK_DIR/simulator"

echo "Downloading OpenCV ${VERSION} iOS device binary..."
curl --fail --location --retry 3 --retry-delay 2 "${BASE_URL}/${DEVICE_ZIP}" -o "${WORK_DIR}/${DEVICE_ZIP}"
echo "${DEVICE_SHA256}  ${WORK_DIR}/${DEVICE_ZIP}" | shasum -a 256 -c -

echo "Downloading OpenCV ${VERSION} iOS Simulator binary..."
curl --fail --location --retry 3 --retry-delay 2 "${BASE_URL}/${SIMULATOR_ZIP}" -o "${WORK_DIR}/${SIMULATOR_ZIP}"
echo "${SIMULATOR_SHA256}  ${WORK_DIR}/${SIMULATOR_ZIP}" | shasum -a 256 -c -

unzip -q "${WORK_DIR}/${DEVICE_ZIP}" -d "${WORK_DIR}/device"
unzip -q "${WORK_DIR}/${SIMULATOR_ZIP}" -d "${WORK_DIR}/simulator"

DEVICE_FRAMEWORK="$(find "${WORK_DIR}/device" -type d -name opencv2.framework -print -quit)"
SIMULATOR_FRAMEWORK="$(find "${WORK_DIR}/simulator" -type d -name opencv2.framework -print -quit)"

if [ -z "$DEVICE_FRAMEWORK" ] || [ -z "$SIMULATOR_FRAMEWORK" ]; then
  echo "::error::Could not find opencv2.framework in the downloaded archives."
  find "$WORK_DIR" -maxdepth 5 -print
  exit 1
fi

if [ ! -f "$DEVICE_FRAMEWORK/Headers/opencv2/opencv.hpp" ]; then
  echo "::error::opencv2/opencv.hpp is missing from the device framework."
  exit 1
fi

if ! grep -R -q "inpaint" "$DEVICE_FRAMEWORK/Headers"; then
  echo "::error::OpenCV photo/inpaint API is missing from this package."
  exit 1
fi

xcodebuild -create-xcframework -framework "$DEVICE_FRAMEWORK" -framework "$SIMULATOR_FRAMEWORK" -output "$OUTPUT_DIR"

test -f "$OUTPUT_DIR/Info.plist"
FRAMEWORK_COUNT="$(find "$OUTPUT_DIR" -type d -name opencv2.framework | wc -l | tr -d ' ')"
if [ "$FRAMEWORK_COUNT" -lt 2 ]; then
  echo "::error::Expected device and simulator OpenCV framework slices."
  exit 1
fi

rm -rf "$WORK_DIR"
echo "OpenCV ${VERSION} XCFramework ready at ${OUTPUT_DIR}."
