#import "SuperResApp-Bridging-Header.h"
#import <opencv2/opencv.hpp>

#include <limits>

static NSString * const OpenCVBridgeErrorDomain = @"OpenCVBridge";

static void SetBridgeError(NSError **error, NSInteger code, NSString *message) {
    if (error != nullptr) {
        *error = [NSError errorWithDomain:OpenCVBridgeErrorDomain
                                     code:code
                                 userInfo:@{NSLocalizedDescriptionKey: message}];
    }
}

/// Repairs BGRA pixels under a single-channel mask using Telea inpainting.
/// The input alpha channel is preserved unchanged.
///
/// opencv-mobile is built without C++ exceptions and RTTI. Validate all
/// externally controlled arguments before calling OpenCV; do not catch cv::Exception.
NSData * _Nullable inpaintImage(NSData *imageData,
                                NSData *maskData,
                                int width,
                                int height,
                                int radius,
                                NSError **error) {
    if (imageData == nil || maskData == nil || width <= 0 || height <= 0 || radius <= 0) {
        SetBridgeError(error, -1, @"Invalid image, mask, dimensions, or inpaint radius.");
        return nil;
    }

    const size_t pixelWidth = static_cast<size_t>(width);
    const size_t pixelHeight = static_cast<size_t>(height);
    if (pixelWidth > std::numeric_limits<size_t>::max() / pixelHeight) {
        SetBridgeError(error, -2, @"Image dimensions overflow the supported buffer size.");
        return nil;
    }

    const size_t pixelCount = pixelWidth * pixelHeight;
    if (pixelCount > std::numeric_limits<size_t>::max() / 4) {
        SetBridgeError(error, -2, @"Image buffer size overflow.");
        return nil;
    }

    const size_t expectedImageBytes = pixelCount * 4;
    if (imageData.length != expectedImageBytes || maskData.length != pixelCount) {
        SetBridgeError(error, -3, @"Image or mask byte count does not match its dimensions.");
        return nil;
    }

    cv::Mat sourceBGRA(height, width, CV_8UC4, const_cast<void *>(imageData.bytes));
    cv::Mat mask(height, width, CV_8UC1, const_cast<void *>(maskData.bytes));
    cv::Mat sourceBGR;
    cv::Mat repairedBGR;
    cv::cvtColor(sourceBGRA, sourceBGR, CV_BGRA2BGR);
    cv::inpaint(sourceBGR, mask, repairedBGR, static_cast<double>(radius), cv::INPAINT_TELEA);

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
