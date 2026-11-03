#import "SuperResApp-Bridging-Header.h"
#import <opencv2/opencv.hpp>

#include <cstdint>
#include <cmath>
#include <cstdlib>
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


/// Scores how smoothly a candidate reconstruction joins the untouched image.
/// Only pixels on the mask boundary are evaluated; lower is better.
static double BoundaryContinuityScore(const cv::Mat &original,
                                      const cv::Mat &candidate,
                                      const cv::Mat &mask) {
    double totalDifference = 0.0;
    size_t samples = 0;
    for (int y = 0; y < mask.rows; ++y) {
        const uint8_t *maskRow = mask.ptr<uint8_t>(y);
        const cv::Vec3b *candidateRow = candidate.ptr<cv::Vec3b>(y);
        for (int x = 0; x < mask.cols; ++x) {
            if (maskRow[x] == 0) {
                continue;
            }
            const int dx[4] = {-1, 1, 0, 0};
            const int dy[4] = {0, 0, -1, 1};
            for (int direction = 0; direction < 4; ++direction) {
                const int nx = x + dx[direction];
                const int ny = y + dy[direction];
                if (nx < 0 || ny < 0 || nx >= mask.cols || ny >= mask.rows
                    || mask.ptr<uint8_t>(ny)[nx] != 0) {
                    continue;
                }
                const cv::Vec3b neighbor = original.at<cv::Vec3b>(ny, nx);
                for (int channel = 0; channel < 3; ++channel) {
                    totalDifference += std::abs(
                        static_cast<int>(candidateRow[x][channel])
                        - static_cast<int>(neighbor[channel])
                    );
                    ++samples;
                }
            }
        }
    }
    return samples == 0 ? std::numeric_limits<double>::max()
                        : totalDifference / static_cast<double>(samples);
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


/// Finds a clean donor patch whose visible context best matches the target ROI.
/// The coarse search is performed at quarter resolution; final ranking compares
/// color and gradient structure at full resolution. Returns false when no safe,
/// sufficiently similar donor exists so the caller can use classical inpainting.
static bool FindBestBackgroundPatch(const cv::Mat &sourceBGR,
                                    const cv::Mat &mask,
                                    const cv::Rect &targetRect,
                                    cv::Mat &donorPatch,
                                    double &bestScore) {
    const cv::Mat targetBGR = sourceBGR(targetRect);
    const cv::Mat targetMask = mask(targetRect);
    cv::Mat visibleContext;
    cv::bitwise_not(targetMask, visibleContext);
    if (cv::countNonZero(visibleContext) < 64) {
        return false;
    }

    cv::Mat sourceGray;
    cv::Mat targetGray;
    cv::cvtColor(sourceBGR, sourceGray, CV_BGR2GRAY);
    cv::cvtColor(targetBGR, targetGray, CV_BGR2GRAY);

    constexpr double searchScale = 0.25;
    cv::Mat sourceSmall;
    cv::Mat targetSmall;
    cv::Mat contextSmall;
    cv::resize(sourceGray, sourceSmall, cv::Size(), searchScale, searchScale, cv::INTER_AREA);
    cv::resize(targetGray, targetSmall, cv::Size(), searchScale, searchScale, cv::INTER_AREA);
    cv::resize(visibleContext, contextSmall, targetSmall.size(), 0, 0, cv::INTER_NEAREST);

    if (targetSmall.cols < 8 || targetSmall.rows < 8
        || sourceSmall.cols <= targetSmall.cols || sourceSmall.rows <= targetSmall.rows
        || cv::countNonZero(contextSmall) < 16) {
        return false;
    }

    // Build a coarse masked score map manually. The bundled opencv-mobile
    // omits matchTemplate's mask overload, so only visible context pixels are
    // sampled here. A two-pixel stride keeps the search bounded on-device.
    const int scoreRows = sourceSmall.rows - targetSmall.rows + 1;
    const int scoreColumns = sourceSmall.cols - targetSmall.cols + 1;
    cv::Mat matchScores(scoreRows, scoreColumns, CV_32F, cv::Scalar(1.0));
    for (int candidateY = 0; candidateY < scoreRows; candidateY += 2) {
        for (int candidateX = 0; candidateX < scoreColumns; candidateX += 2) {
            double difference = 0.0;
            size_t samples = 0;
            for (int y = 0; y < targetSmall.rows; y += 2) {
                const uint8_t *contextRow = contextSmall.ptr<uint8_t>(y);
                const uint8_t *targetRow = targetSmall.ptr<uint8_t>(y);
                const uint8_t *candidateRow = sourceSmall.ptr<uint8_t>(candidateY + y)
                    + candidateX;
                for (int x = 0; x < targetSmall.cols; x += 2) {
                    if (contextRow[x] == 0) {
                        continue;
                    }
                    difference += std::abs(
                        static_cast<int>(targetRow[x]) - static_cast<int>(candidateRow[x])
                    ) / 255.0;
                    ++samples;
                }
            }
            if (samples >= 16) {
                matchScores.at<float>(candidateY, candidateX) =
                    static_cast<float>(difference / static_cast<double>(samples));
            }
        }
    }

    // An integral mask lets us reject donor rectangles that contain any part
    // of the subtitle itself, including another line of text.
    cv::Mat maskBinaryForIntegral;
    mask.convertTo(maskBinaryForIntegral, CV_8U, 1.0 / 255.0);
    cv::Mat maskIntegral;
    // Store 0/1 rather than 0/255 so a 16 MP mask cannot overflow CV_32S.
    cv::integral(maskBinaryForIntegral, maskIntegral, CV_32S);

    cv::Mat targetGradientX;
    cv::Mat targetGradientY;
    cv::Mat targetGradient;
    cv::Sobel(targetGray, targetGradientX, CV_32F, 1, 0, 3);
    cv::Sobel(targetGray, targetGradientY, CV_32F, 0, 1, 3);
    cv::magnitude(targetGradientX, targetGradientY, targetGradient);

    bestScore = std::numeric_limits<double>::max();
    cv::Point bestLocation(-1, -1);
    const int targetWidth = targetRect.width;
    const int targetHeight = targetRect.height;
    const int candidateCount = 24;
    const double maximumScore = 0.24;

    for (int candidateIndex = 0; candidateIndex < candidateCount; ++candidateIndex) {
        double coarseScore = 0.0;
        cv::Point coarseLocation;
        cv::minMaxLoc(matchScores, &coarseScore, nullptr, &coarseLocation, nullptr);
        if (!std::isfinite(coarseScore) || coarseScore >= 1.0) {
            break;
        }
        const int suppressX = std::max(0, coarseLocation.x - targetSmall.cols / 2);
        const int suppressY = std::max(0, coarseLocation.y - targetSmall.rows / 2);
        const cv::Rect suppressRect(
            suppressX,
            suppressY,
            std::min(targetSmall.cols, matchScores.cols - suppressX),
            std::min(targetSmall.rows, matchScores.rows - suppressY)
        );
        matchScores(suppressRect).setTo(cv::Scalar(1.0));

        const int candidateX = static_cast<int>(std::lround(coarseLocation.x / searchScale));
        const int candidateY = static_cast<int>(std::lround(coarseLocation.y / searchScale));
        if (candidateX < 0 || candidateY < 0
            || candidateX + targetWidth > sourceBGR.cols
            || candidateY + targetHeight > sourceBGR.rows) {
            continue;
        }

        const int x0 = candidateX;
        const int y0 = candidateY;
        const int x1 = candidateX + targetWidth;
        const int y1 = candidateY + targetHeight;
        const int maskedPixels = maskIntegral.at<int>(y1, x1)
            - maskIntegral.at<int>(y0, x1)
            - maskIntegral.at<int>(y1, x0)
            + maskIntegral.at<int>(y0, x0);
        if (maskedPixels != 0) {
            continue;
        }

        const cv::Rect candidateRect(candidateX, candidateY, targetWidth, targetHeight);
        const cv::Mat candidateBGR = sourceBGR(candidateRect);
        cv::Mat candidateGray;
        cv::cvtColor(candidateBGR, candidateGray, CV_BGR2GRAY);
        cv::Mat candidateGradientX;
        cv::Mat candidateGradientY;
        cv::Mat candidateGradient;
        cv::Sobel(candidateGray, candidateGradientX, CV_32F, 1, 0, 3);
        cv::Sobel(candidateGray, candidateGradientY, CV_32F, 0, 1, 3);
        cv::magnitude(candidateGradientX, candidateGradientY, candidateGradient);

        double colorDifference = 0.0;
        double gradientDifference = 0.0;
        size_t samples = 0;
        for (int y = 0; y < targetHeight; ++y) {
            const uint8_t *visibleRow = visibleContext.ptr<uint8_t>(y);
            const cv::Vec3b *targetRow = targetBGR.ptr<cv::Vec3b>(y);
            const cv::Vec3b *candidateRow = candidateBGR.ptr<cv::Vec3b>(y);
            const float *targetGradientRow = targetGradient.ptr<float>(y);
            const float *candidateGradientRow = candidateGradient.ptr<float>(y);
            for (int x = 0; x < targetWidth; ++x) {
                if (visibleRow[x] == 0) {
                    continue;
                }
                for (int channel = 0; channel < 3; ++channel) {
                    colorDifference += std::abs(
                        static_cast<int>(targetRow[x][channel])
                        - static_cast<int>(candidateRow[x][channel])
                    ) / 765.0;
                }
                gradientDifference += std::min(
                    1.0,
                    std::abs(targetGradientRow[x] - candidateGradientRow[x]) / 1442.0
                );
                ++samples;
            }
        }
        if (samples == 0) {
            continue;
        }

        const double score = 0.70 * (colorDifference / static_cast<double>(samples))
            + 0.30 * (gradientDifference / static_cast<double>(samples));
        if (score < bestScore) {
            bestScore = score;
            bestLocation = cv::Point(candidateX, candidateY);
        }
        if (bestScore <= maximumScore) {
            break;
        }
    }

    if (bestLocation.x < 0 || bestScore > maximumScore) {
        return false;
    }
    donorPatch = sourceBGR(cv::Rect(bestLocation.x, bestLocation.y,
                                    targetWidth, targetHeight)).clone();
    return true;
}

/// Repairs a subtitle region with confidence-gated texture donors and classical fallbacks.
/// Donor patches must match visible context and must not overlap any masked pixels.
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

    // Restrict both candidate algorithms to a padded mask ROI. This keeps the
    // two-pass strategy affordable for full-resolution portrait screenshots.
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

    // Keep the search radius proportional to the subtitle stroke scale. Large
    // radii spread colors farther and are a common source of broad smearing.
    const double adaptiveRadius = static_cast<double>(std::min<NSInteger>(radius, 5));
    const int padding = std::max(8, static_cast<int>(adaptiveRadius * 3.0));
    const int roiX = std::max(0, minX - padding);
    const int roiY = std::max(0, minY - padding);
    const int roiRight = std::min(imageWidth, maxX + 1 + padding);
    const int roiBottom = std::min(imageHeight, maxY + 1 + padding);
    const cv::Rect repairRect(roiX, roiY, roiRight - roiX, roiBottom - roiY);
    const cv::Mat maskRegion = mask(repairRect);

    cv::Mat sourceBGR;
    cv::cvtColor(sourceBGRA, sourceBGR, CV_BGRA2BGR);
    const cv::Mat sourceBGRRegion = sourceBGR(repairRect);

    cv::Mat donorPatch;
    double donorScore = std::numeric_limits<double>::max();
    const bool hasConfidentDonor = FindBestBackgroundPatch(
        sourceBGR, mask, repairRect, donorPatch, donorScore
    );

    cv::Mat teleaCandidate;
    cv::Mat nsCandidate;
    cv::inpaint(sourceBGRRegion, maskRegion, teleaCandidate, adaptiveRadius, cv::INPAINT_TELEA);
    cv::inpaint(sourceBGRRegion, maskRegion, nsCandidate, adaptiveRadius, cv::INPAINT_NS);

    const double teleaScore = BoundaryContinuityScore(sourceBGRRegion, teleaCandidate, maskRegion);
    const double nsScore = BoundaryContinuityScore(sourceBGRRegion, nsCandidate, maskRegion);
    const cv::Mat &classicalCandidate = teleaScore <= nsScore ? teleaCandidate : nsCandidate;

    // Prefer a donor patch only when its visible context is a close color and
    // gradient match. Otherwise retain the safer classical reconstruction.
    const cv::Mat &selectedBGR = hasConfidentDonor ? donorPatch : classicalCandidate;

    // Composite only masked pixels here. Soft edge blending is performed by
    // InpaintEngine using RasterizedMask.softWeights, never inside OpenCV.
    cv::Mat outputBGRA = sourceBGRA.clone();
    for (int y = 0; y < repairRect.height; ++y) {
        const uint8_t *maskRow = maskRegion.ptr<uint8_t>(y);
        const cv::Vec3b *repairedRow = selectedBGR.ptr<cv::Vec3b>(y);
        cv::Vec4b *outputRow = outputBGRA.ptr<cv::Vec4b>(roiY + y) + roiX;
        for (int x = 0; x < repairRect.width; ++x) {
            if (maskRow[x] == 0) {
                continue;
            }
            outputRow[x][0] = repairedRow[x][0];
            outputRow[x][1] = repairedRow[x][1];
            outputRow[x][2] = repairedRow[x][2];
            // Alpha is intentionally preserved from the source.
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
