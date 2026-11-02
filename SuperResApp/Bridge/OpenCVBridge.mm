#import "SuperResApp-Bridging-Header.h"
#import <opencv2/opencv.hpp>

#include <cstdint>
#include <limits>

static NSString * const OpenCVBridgeErrorDomain = @"OpenCVBridge";
static const size_t kMaxPixels = 16u * 1024u * 1024u;
static const int kMaxSide = 8192;
static const int kMaxRadius = 20;

static void SetBridgeError(NSError **error, NSInteger code, NSString *message) {
    if (error != nullptr) {
        *error = [NSError errorWithDomain:OpenCVBridgeErrorDomain
                                     code:code
                                 userInfo:@{NSLocalizedDescriptionKey: message}];
    }
}

/// Returns 0 when repair is safe, -1 for an empty mask, and -2 when the
/// mask leaves too little trustworthy reference content.
static int ValidateMask(const uint8_t *bytes, int width, int height) {
    size_t maskedPixels = 0;
    bool touchesImageEdge = false;
    const size_t totalPixels = static_cast<size_t>(width) * static_cast<size_t>(height);

    for (int y = 0; y < height; ++y) {
        for (int x = 0; x < width; ++x) {
            if (bytes[static_cast<size_t>(y) * static_cast<size_t>(width)
                      + static_cast<size_t>(x)] == 0) {
                continue;
            }
            ++maskedPixels;
            if (x == 0 || y == 0 || x == width - 1 || y == height - 1) {
                touchesImageEdge = true;
            }
        }
    }

    if (maskedPixels == 0) {
        return -1;
    }

    // Count distinct unmasked pixels directly adjacent to the masked region.
    // These are the actual boundary samples available to seed Telea's front.
    size_t boundaryReferencePixels = 0;
    for (int y = 0; y < height; ++y) {
        for (int x = 0; x < width; ++x) {
            const size_t index = static_cast<size_t>(y) * static_cast<size_t>(width)
                + static_cast<size_t>(x);
            if (bytes[index] != 0) {
                continue;
            }

            const bool adjacentToMask =
                (x > 0 && bytes[index - 1] != 0)
                || (x + 1 < width && bytes[index + 1] != 0)
                || (y > 0 && bytes[index - static_cast<size_t>(width)] != 0)
                || (y + 1 < height && bytes[index + static_cast<size_t>(width)] != 0);
            if (adjacentToMask) {
                ++boundaryReferencePixels;
            }
        }
    }
    if (boundaryReferencePixels < 4) {
        return -2;
    }

    const double coverage = static_cast<double>(maskedPixels)
        / static_cast<double>(totalPixels);
    if (coverage > 0.95 && touchesImageEdge) {
        return -2;
    }
    return 0;
}

/// Repairs BGRA pixels under a single-channel mask using Telea inpainting.
/// Input alpha is copied back unchanged.
///
/// SAFETY CONTRACT: opencv-mobile is built without C++ exceptions and RTTI.
/// All external input validation and mask short-circuits must happen before
/// constructing cv::Mat or calling OpenCV. Never add C++ exception handlers.
NSData * _Nullable inpaintImage(NSData *imageData,
                                NSData *maskData,
                                int width,
                                int height,
                                int radius,
                                NSError **error) {
    // 1. Dimensions and total pixel count: reject before buffer arithmetic or Mat.
    if (imageData == nil || maskData == nil || width < 1 || height < 1
        || width > kMaxSide || height > kMaxSide) {
        SetBridgeError(error, 1002, @"Image dimensions are outside the supported range.");
        return nil;
    }

    const size_t pixelWidth = static_cast<size_t>(width);
    const size_t pixelHeight = static_cast<size_t>(height);
    if (pixelWidth > std::numeric_limits<size_t>::max() / pixelHeight) {
        SetBridgeError(error, 1002, @"Image dimensions overflow the supported buffer size.");
        return nil;
    }
    const size_t pixelCount = pixelWidth * pixelHeight;
    if (pixelCount > kMaxPixels) {
        SetBridgeError(error, 1002, @"Image pixel count exceeds the 16 MP limit.");
        return nil;
    }

    // 2. Radius contract.
    if (radius < 1 || radius > kMaxRadius) {
        SetBridgeError(error, 4001, @"Inpaint radius must be between 1 and 20.");
        return nil;
    }

    // 3. Exact buffer lengths, after safe pixel-count calculation.
    if (pixelCount > std::numeric_limits<size_t>::max() / 4u) {
        SetBridgeError(error, 1002, @"Image buffer size overflows the supported range.");
        return nil;
    }
    const size_t expectedImageBytes = pixelCount * 4u;
    if (imageData.length != expectedImageBytes || maskData.length != pixelCount) {
        SetBridgeError(error, 4002, @"Image or mask byte count does not match its dimensions.");
        return nil;
    }

    const uint8_t *imageBytes = static_cast<const uint8_t *>(imageData.bytes);
    const uint8_t *maskBytes = static_cast<const uint8_t *>(maskData.bytes);

    // 4. Mask semantics: empty mask is a true no-OpenCV short circuit.
    const int maskState = ValidateMask(maskBytes, width, height);
    if (maskState == -1) {
        return [imageData copy];
    }
    if (maskState == -2) {
        SetBridgeError(error, 4001, @"Mask leaves fewer than four valid reference pixels.");
        return nil;
    }

    // 5. Only validated inputs reach OpenCV.
    cv::Mat sourceBGRA(height, width, CV_8UC4, const_cast<uint8_t *>(imageBytes));
    cv::Mat mask(height, width, CV_8UC1, const_cast<uint8_t *>(maskBytes));
    cv::Mat sourceBGR;
    cv::Mat repairedBGR;
    cv::cvtColor(sourceBGRA, sourceBGR, CV_BGRA2BGR);
    cv::inpaint(sourceBGR, mask, repairedBGR, static_cast<double>(radius), cv::INPAINT_TELEA);

    // 6. Restore original alpha byte-for-byte.
    cv::Mat outputBGRA(height, width, CV_8UC4);
    for (int row = 0; row < height; ++row) {
        const cv::Vec3b *repairedPixels = repairedBGR.ptr<cv::Vec3b>(row);
        const cv::Vec4b *sourcePixels = sourceBGRA.ptr<cv::Vec4b>(row);
        cv::Vec4b *outputPixels = outputBGRA.ptr<cv::Vec4b>(row);
        for (int column = 0; column < width; ++column) {
            outputPixels[column][0] = repairedPixels[column][0];
            outputPixels[column][1] = repairedPixels[column][1];
            outputPixels[column][2] = repairedPixels[column][2];
            outputPixels[column][3] = sourcePixels[column][3];
        }
    }

    return [NSData dataWithBytes:outputBGRA.data
                          length:outputBGRA.total() * outputBGRA.elemSize()];
}
