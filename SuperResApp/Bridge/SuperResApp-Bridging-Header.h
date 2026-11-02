//
//  SuperResApp-Bridging-Header.h
//  Exposes the Objective-C-compatible OpenCV bridge to Swift.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT NSData * _Nullable inpaintImage(
    NSData *imageData,
    NSData *maskData,
    int width,
    int height,
    int radius,
    NSError * _Nullable * _Nullable error
) NS_SWIFT_NOTHROW;

NS_ASSUME_NONNULL_END
