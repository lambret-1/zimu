#import "SuperResApp-Bridging-Header.h"
#import <opencv2/opencv.hpp>

#if CV_MAJOR_VERSION >= 3 && __has_include(<opencv2/photo.hpp>)
#import <opencv2/photo.hpp>
#define SUPERRES_HAS_SEAMLESS_CLONE 1
#else
#define SUPERRES_HAS_SEAMLESS_CLONE 0
#endif

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
    cv::inpaint(sourceBGR, mask, repairedBGR, static_cast<double>(radius), cv::INPAINT_NS);

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


/// Repairs a subtitle region by borrowing a clean vertically adjacent background patch.
/// Uses Poisson seamless cloning when the linked OpenCV version exposes it; otherwise
/// performs feathered texture transfer. Telea is reserved for cases without a clean donor.
NSData * _Nullable SuperResAdvancedInpaint(NSData *imageData,
                                            NSData *maskData,
                                            NSInteger width,
                                            NSInteger height,
                                            NSInteger radius,
                                            NSError **error) {
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
    if (pixelCount > kMaxPixels || pixelCount > std::numeric_limits<size_t>::max() / 4u) {
        SetBridgeError(error, 1002, @"Image exceeds the supported pixel limit.");
        return nil;
    }
    if (radius < 1 || radius > kMaxRadius) {
        SetBridgeError(error, 4001, @"Inpaint radius must be between 1 and 20.");
        return nil;
    }

    const size_t expectedImageBytes = pixelCount * 4u;
    if (imageData.length != expectedImageBytes || maskData.length != pixelCount) {
        SetBridgeError(error, 4002, @"Image or mask byte count does not match its dimensions.");
        return nil;
    }

    const uint8_t *imageBytes = static_cast<const uint8_t *>(imageData.bytes);
    const uint8_t *maskBytes = static_cast<const uint8_t *>(maskData.bytes);
    const int imageWidth = static_cast<int>(width);
    const int imageHeight = static_cast<int>(height);
    const int maskState = ValidateMask(maskBytes, imageWidth, imageHeight);
    if (maskState == -1) {
        return [imageData copy];
    }
    if (maskState == -2) {
        SetBridgeError(error, 4001, @"Mask leaves fewer than four valid reference pixels.");
        return nil;
    }

    cv::Mat sourceBGRA(imageHeight, imageWidth, CV_8UC4, const_cast<uint8_t *>(imageBytes));
    cv::Mat mask(imageHeight, imageWidth, CV_8UC1, const_cast<uint8_t *>(maskBytes));

    // Find tight bounds without allocating a potentially huge Point vector.
    int minX = imageWidth;
    int minY = imageHeight;
    int maxX = -1;
    int maxY = -1;
    for (int y = 0; y < imageHeight; ++y) {
        const uint8_t *maskRow = mask.ptr<uint8_t>(y);
        for (int x = 0; x < imageWidth; ++x) {
            if (maskRow[x] == 0) {
                continue;
            }
            minX = std::min(minX, x);
            minY = std::min(minY, y);
            maxX = std::max(maxX, x);
            maxY = std::max(maxY, y);
        }
    }
    if (maxX < minX || maxY < minY) {
        return [imageData copy];
    }

    const int padding = 10;
    const int roiX = std::max(0, minX - padding);
    const int roiY = std::max(0, minY - padding);
    const int roiRight = std::min(imageWidth, maxX + 1 + padding);
    const int roiBottom = std::min(imageHeight, maxY + 1 + padding);
    const cv::Rect targetRect(roiX, roiY, roiRight - roiX, roiBottom - roiY);

    cv::Mat sourceBGR;
    cv::cvtColor(sourceBGRA, sourceBGR, CV_BGRA2BGR);

    // Prefer the region directly above the subtitle; try below if unavailable or dirty.
    cv::Rect donorRect;
    bool hasCleanDonor = false;
    const int donorY[2] = {
        targetRect.y - targetRect.height,
        targetRect.y + targetRect.height
    };
    for (int candidate = 0; candidate < 2 && !hasCleanDonor; ++candidate) {
        const int y = donorY[candidate];
        if (y < 0 || y + targetRect.height > imageHeight) {
            continue;
        }
        const cv::Rect candidateRect(targetRect.x, y, targetRect.width, targetRect.height);
        if (cv::countNonZero(mask(candidateRect)) == 0) {
            donorRect = candidateRect;
            hasCleanDonor = true;
        }
    }

    cv::Mat repairedBGR;
    if (hasCleanDonor) {
        const cv::Mat donorPatch = sourceBGR(donorRect).clone();
        cv::Mat blendMask;
        cv::compare(mask(targetRect), cv::Scalar(0), blendMask, CV_CMP_GT);
        const cv::Mat edgeKernel = cv::getStructuringElement(
            cv::MORPH_ELLIPSE, cv::Size(7, 7));
        cv::dilate(blendMask, blendMask, edgeKernel);
        cv::GaussianBlur(blendMask, blendMask, cv::Size(7, 7), 0);

#if SUPERRES_HAS_SEAMLESS_CLONE
        const cv::Point center(
            targetRect.x + targetRect.width / 2,
            targetRect.y + targetRect.height / 2
        );
        cv::seamlessClone(
            donorPatch, sourceBGR, blendMask, center, repairedBGR, cv::NORMAL_CLONE
        );
#else
        // The pinned opencv-mobile 2.4.x binary has no seamlessClone API.
        // Preserve donor texture with a feathered alpha blend instead.
        repairedBGR = sourceBGR.clone();
        cv::Mat targetPatch = repairedBGR(targetRect);
        for (int y = 0; y < targetRect.height; ++y) {
            const uint8_t *weights = blendMask.ptr<uint8_t>(y);
            const cv::Vec3b *donorPixels = donorPatch.ptr<cv::Vec3b>(y);
            cv::Vec3b *targetPixels = targetPatch.ptr<cv::Vec3b>(y);
            for (int x = 0; x < targetRect.width; ++x) {
                const double weight = static_cast<double>(weights[x]) / 255.0;
                if (weight <= 0.0) {
                    continue;
                }
                for (int channel = 0; channel < 3; ++channel) {
                    const double originalValue = static_cast<double>(targetPixels[x][channel]);
                    const double donorValue = static_cast<double>(donorPixels[x][channel]);
                    targetPixels[x][channel] = cv::saturate_cast<uint8_t>(
                        originalValue * (1.0 - weight) + donorValue * weight
                    );
                }
            }
        }
#endif
    } else {
        // No trustworthy donor patch: use a small Telea radius to avoid broad smearing.
        const double fallbackRadius = static_cast<double>(std::min<NSInteger>(radius, 3));
        cv::inpaint(sourceBGR, mask, repairedBGR, fallbackRadius, cv::INPAINT_TELEA);
    }

    cv::Mat outputBGRA;
    cv::cvtColor(repairedBGR, outputBGRA, CV_BGR2BGRA);
    for (int y = 0; y < imageHeight; ++y) {
        const cv::Vec4b *sourcePixels = sourceBGRA.ptr<cv::Vec4b>(y);
        cv::Vec4b *outputPixels = outputBGRA.ptr<cv::Vec4b>(y);
        for (int x = 0; x < imageWidth; ++x) {
            outputPixels[x][3] = sourcePixels[x][3];
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
    if (dilateRadius < 0 || dilateRadius > kMaxRadius) {
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

    // Keep both polarities: outlined subtitles commonly contain bright fills and
    // dark strokes in the same coarse Vision region.
    cv::Mat textMask;
    cv::bitwise_or(binaryLight, binaryDark, textMask);
    const double coarseArea = cv::countNonZero(roiCoarse);

    if (cv::countNonZero(textMask) == 0) {
        // Vision's coarse rectangle is safer than returning an empty mask: the
        // caller must still be able to remove text that morphology did not isolate.
        cv::Mat fallback = cv::Mat::zeros(
            static_cast<int>(height), static_cast<int>(width), CV_8UC1);
        roiCoarse.copyTo(fallback(roiRect));
        return [NSData dataWithBytes:fallback.data
                              length:fallback.total() * fallback.elemSize()];
    }

    cv::morphologyEx(textMask, textMask, cv::MORPH_CLOSE, topHatKernel);
    std::vector<std::vector<cv::Point>> contours;
    cv::findContours(textMask.clone(), contours, cv::RETR_EXTERNAL, cv::CHAIN_APPROX_SIMPLE);
    cv::Mat cleanMask = cv::Mat::zeros(textMask.size(), CV_8UC1);
    // Keep small punctuation/dots while rejecting isolated single-pixel noise.
    const double minimumArea = std::max(1.0, coarseArea * 0.0005);
    for (size_t index = 0; index < contours.size(); ++index) {
        if (cv::contourArea(contours[index]) >= minimumArea) {
            cv::drawContours(cleanMask, contours, static_cast<int>(index),
                             cv::Scalar(255), -1);
        }
    }
    if (cv::countNonZero(cleanMask) == 0) {
        // Preserve the coarse Vision region if component filtering rejected
        // every candidate; never turn a detected subtitle into an empty mask.
        cleanMask = roiCoarse.clone();
    }

    // Fixed pixel-radius dilation: the app passes 3 px to cover subtitle outlines.
    const int dilationSize = static_cast<int>(dilateRadius) * 2 + 1;
    const cv::Mat dilationKernel = cv::getStructuringElement(
        cv::MORPH_ELLIPSE, cv::Size(dilationSize, dilationSize));
    cv::Mat dilatedMask;
    cv::dilate(cleanMask, dilatedMask, dilationKernel);

    cv::Mat fullMask = cv::Mat::zeros(
        static_cast<int>(height), static_cast<int>(width), CV_8UC1);
    dilatedMask.copyTo(fullMask(roiRect));

    // This bridge returns a binary 0/255 repair mask only. Feather weights
    // are generated separately in Swift and are never passed to OpenCV.
    return [NSData dataWithBytes:fullMask.data
                          length:fullMask.total() * fullMask.elemSize()];
}
