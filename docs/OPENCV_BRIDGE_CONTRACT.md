# OpenCV Bridge Safety Contract

This contract applies to `inpaintImage`, `SuperResAdvancedInpaint`, and
`SuperResRefineSubtitleMask` in `SuperResApp/Bridge/OpenCVBridge.mm`.

## Why validation must happen before OpenCV

The pinned opencv-mobile binary is built with C++ exceptions and RTTI disabled.
A failed OpenCV assertion or allocation can terminate the process; there is no
reliable `cv::Exception` / `std::bad_alloc` catch path. Do not add C++ or
Objective-C exception handlers as a substitute for input validation.

## Required short-circuit order

Both inpaint entry points must preserve this order. No `cv::Mat`, `cvtColor`,
`cv::inpaint`, or donor-patch operation may occur before all applicable checks
have passed.

| Order | Contract | Failure behavior |
|---|---|---|
| 1 | Non-null buffers; width and height each in 1...8192 | E1002 / `mediaTooLarge` |
| 2 | Safe multiplication and total pixels ≤ 16,777,216 | E1002 / `mediaTooLarge` |
| 3 | Radius in 1...20 | E4001 / `inpaintFailed` |
| 4 | Image byte count exactly width × height × 4; mask byte count exactly width × height | E4002 / `openCVBridgeError` |
| 5 | All-zero mask | Return an exact copy of the original BGRA buffer; do not call OpenCV |
| 6 | Mask coverage >95% and at least one masked pixel touches an image edge | E4001 / `inpaintFailed` |
| 7 | At least four distinct unmasked pixels directly adjacent to the mask boundary | E4001 / `inpaintFailed` |

The bridge revalidates these rules even when Swift has already validated them.
Swift validation is an early user-facing guard, not a replacement for the
Objective-C++ boundary checks.

## Pixel and alpha contract

- Input is tightly packed BGRA8888; mask is tightly packed 8-bit single-channel.
- Telea receives BGR + 8UC1 only.
- Advanced repair searches clean same-size patches above, then below the mask ROI.
- OpenCV 3+ builds with photo headers use `seamlessClone` on BGR data and a feathered single-channel mask.
- The pinned opencv-mobile 2.4.x build has no `seamlessClone`; it uses feathered donor-patch blending. Telea is used only when no clean donor exists.
- Output is BGRA8888 with the source alpha channel copied byte-for-byte.
- No C++ OpenCV headers or C++ types may leak into the Swift bridging header.
- Do not add `try/catch`, `catch (cv::Exception)`, or `@try/@catch` around
  OpenCV calls. Keep all deterministic validation before OpenCV entry.

Mask refinement uses the supplied fixed dilation radius (the app passes 3 px)
and feather radius (2 px); text-extraction morphology remains independent.

## Change checklist

Any change to `OpenCVBridge.mm` must update this contract and include tests
for the changed boundary behavior. Reviewers must verify that validation still
precedes Mat construction and every OpenCV call.
