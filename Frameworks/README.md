# OpenCV Frameworks

The OpenCV binary is intentionally not committed to Git. Run the pinned setup script on a Mac with Xcode installed:

```bash
bash ./Scripts/setup-opencv.sh
xcodegen generate
```

The script downloads the OpenCV Mobile v37 (OpenCV 2.4.13.7) iOS device and iOS Simulator archives, verifies their SHA-256 digests, and combines the two `opencv2.framework` slices into `Frameworks/opencv2.xcframework`.

The generated framework directory is ignored by Git. CI runs the same script before XcodeGen, so simulator and generic-device builds use the same pinned binaries without requiring Git LFS or storing vendor binaries in the repository.

Upstream release: https://github.com/nihui/opencv-mobile/releases/tag/v37
