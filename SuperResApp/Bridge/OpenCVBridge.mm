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

    const double coverage = static_cast<double>(maskedPixels)
        / static_cast<double>(totalPixels);
    if (coverage > 0.95 && touchesImageEdge) {
        return -2;
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


/// Extracts subtitle strokes from a coarse region, then pads and feathers the mask.
/// All dimensions and parameters are validated before constructing OpenCV matrices.
NSData * _Nullable SuperResRefineSubtitleMask(NSData *imageData,
                                               NSData *coarseMaskData,
                                               NSInteger width,
                                               NSInteger height,
                                               NSInteger dilateRadius,
                                               NSInteger featherPixels,
                                               NSError **error) {
    if (imageData == nil || coarseMaskData == nil || width < 1 || height < 1
        || width > kMaxSide || height > kMaxSide) {
        SetBridgeError(error, 4002, @"Invalid image dimensions or input buffers.");
        return nil;
    }

    const size_t pixelWidth = static_cast<size_t>(width);
    const size_t pixelHeight = static_cast<size_t>(height);
    if (pixelWidth > std::numeric_limits<size_t>::max() / pixelHeight) {
        SetBridgeError(error, 4002, @"Image dimensions overflow the supported buffer size.");
        return nil;
    }
    const size_t pixelCount = pixelWidth * pixelHeight;
    if (pixelCount > kMaxPixels
        || pixelCount > std::numeric_limits<size_t>::max() / 4u) {
        SetBridgeError(error, 4002, @"Image exceeds the supported pixel limit.");
        return nil;
    }
    if (imageData.length != pixelCount * 4u || coarseMaskData.length != pixelCount) {
        SetBridgeError(error, 4002, @"Buffer size mismatch.");
        return nil;
    }
    if (dilateRadius < 0 || dilateRadius > kMaxRadius
        || featherPixels < 0 || featherPixels > 32) {
        SetBridgeError(error, 4002, @"Refinement radius is outside the supported range.");
        return nil;
    }

    const uint8_t *imageBytes = static_cast<const uint8_t *>(imageData.bytes);
    const uint8_t *maskBytes = static_cast<const uint8_t *>(coarseMaskData.bytes);

    int x0 = static_cast<int>(width);
    int y0 = static_cast<int>(height);
    int x1 = -1;
    int y1 = -1;
    for (int y = 0; y < static_cast<int>(height); ++y) {
        for (int x = 0; x < static_cast<int>(width); ++x) {
            if (maskBytes[static_cast<size_t>(y) * pixelWidth + static_cast<size_t>(x)] == 0) {
                continue;
            }
            x0 = std::min(x0, x);
            x1 = std::max(x1, x);
            y0 = std::min(y0, y);
            y1 = std::max(y1, y);
        }
    }

    if (x1 < x0 || y1 < y0) {
        return [coarseMaskData copy];
    }

    const int textHeight = y1 - y0 + 1;
    int kernelSize = std::max(9, static_cast<int>(textHeight * 0.15));
    if (kernelSize % 2 == 0) {
        ++kernelSize;
    }
    kernelSize = std::min(kernelSize, 255);
    const int margin = std::max(4, kernelSize / 2);
    x0 = std::max(0, x0 - margin);
    y0 = std::max(0, y0 - margin);
    x1 = std::min(static_cast<int>(width) - 1, x1 + margin);
    y1 = std::min(static_cast<int>(height) - 1, y1 + margin);

    const cv::Rect roiRect(x0, y0, x1 - x0 + 1, y1 - y0 + 1);
    cv::Mat sourceBGRA(static_cast<int>(height), static_cast<int>(width), CV_8UC4,
                       const_cast<uint8_t *>(imageBytes));
    cv::Mat coarse(static_cast<int>(height), static_cast<int>(width), CV_8UC1,
                   const_cast<uint8_t *>(maskBytes));
    const cv::Mat roiBGRA = sourceBGRA(roiRect);
    const cv::Mat roiCoarse = coarse(roiRect);

    cv::Mat gray;
    cv::cvtColor(roiBGRA, gray, cv::COLOR_BGRA2GRAY);

    const cv::Mat topHatKernel = cv::getStructuringElement(
        cv::MORPH_RECT, cv::Size(kernelSize, kernelSize));
    cv::Mat topHatLight;
    cv::Mat topHatDark;
    cv::morphologyEx(gray, topHatLight, cv::MORPH_TOPHAT, topHatKernel);
    cv::Mat grayInverse = 255 - gray;
    cv::morphologyEx(grayInverse, topHatDark, cv::MORPH_TOPHAT, topHatKernel);

    cv::Mat binaryLight;
    cv::Mat binaryDark;
    cv::threshold(topHatLight, binaryLight, 0, 255, cv::THRESH_BINARY | cv::THRESH_OTSU);
    cv::threshold(topHatDark, binaryDark, 0, 255, cv::THRESH_BINARY | cv::THRESH_OTSU);
    cv::bitwise_and(binaryLight, roiCoarse, binaryLight);
    cv::bitwise_and(binaryDark, roiCoarse, binaryDark);

    const double lightArea = cv::countNonZero(binaryLight);
    const double darkArea = cv::countNonZero(binaryDark);
    const double coarseArea = cv::countNonZero(roiCoarse);

    cv::Mat textMask;
    if (lightArea >= darkArea && lightArea > 0) {
        textMask = binaryLight;
    } else if (darkArea > lightArea && darkArea > 0) {
        textMask = binaryDark;
    }

    if (textMask.empty()
        || static_cast<double>(cv::countNonZero(textMask)) < coarseArea * 0.02) {
        return [coarseMaskData copy];
    }

    cv::morphologyEx(textMask, textMask, cv::MORPH_CLOSE, topHatKernel);
    std::vector<std::vector<cv::Point>> contours;
    cv::findContours(textMask.clone(), contours, cv::RETR_EXTERNAL, cv::CHAIN_APPROX_SIMPLE);
    cv::Mat cleanMask = cv::Mat::zeros(textMask.size(), CV_8UC1);
    const double minimumArea = std::max(5.0, coarseArea * 0.01);
    for (size_t index = 0; index < contours.size(); ++index) {
        if (cv::contourArea(contours[index]) >= minimumArea) {
            cv::drawContours(cleanMask, contours, static_cast<int>(index),
                             cv::Scalar(255), -1);
        }
    }

    const int dilationSize = static_cast<int>(dilateRadius) * 2 + 1;
    const cv::Mat dilationKernel = cv::getStructuringElement(
        cv::MORPH_ELLIPSE, cv::Size(dilationSize, dilationSize));
    cv::Mat dilatedMask;
    cv::dilate(cleanMask, dilatedMask, dilationKernel);

    cv::Mat fullMask = cv::Mat::zeros(
        static_cast<int>(height), static_cast<int>(width), CV_8UC1);
    dilatedMask.copyTo(fullMask(roiRect));

    if (featherPixels > 0) {
        const int featherSize = static_cast<int>(featherPixels) * 2 + 1;
        cv::Mat blurred;
        cv::GaussianBlur(fullMask, blurred, cv::Size(featherSize, featherSize), 0);
        fullMask.copyTo(blurred, fullMask);
        fullMask = blurred;
    }

    return [NSData dataWithBytes:fullMask.data
                          length:fullMask.total() * fullMask.elemSize()];
}
