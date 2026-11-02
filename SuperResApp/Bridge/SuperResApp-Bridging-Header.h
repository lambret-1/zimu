//
//  SuperResApp-Bridging-Header.h
//  Exposes the Objective-C-compatible OpenCV bridge to Swift.
//

#import <Foundation/Foundation.h>

#ifdef __cplusplus
extern "C" {
#endif

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT NSData * _Nullable inpaintImage(
    NSData *imageData,
    NSData *maskData,
    int width,
    int height,
    int radius,
    NSError * _Nullable * _Nullable error
) NS_SWIFT_NOTHROW;

/// Refines a coarse subtitle mask using local stroke extraction and edge padding.
FOUNDATION_EXPORT NSData * _Nullable SuperResRefineSubtitleMask(
    NSData *imageData,
    NSData *coarseMaskData,
    NSInteger width,
    NSInteger height,
    NSInteger dilateRadius,
    NSInteger featherPixels,
    NSError * _Nullable * _Nullable error
) NS_SWIFT_NAME(superResRefineSubtitleMask(_:_:_:_:dilateRadius:featherPixels:error:))
  NS_SWIFT_NOTHROW;

NS_ASSUME_NONNULL_END

#ifdef __cplusplus
}
#endif
