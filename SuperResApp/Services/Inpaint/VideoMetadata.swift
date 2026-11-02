import AVFoundation
import CoreGraphics
import Foundation

/// Video metadata. Values are immutable after loading.
struct VideoMetadata: Equatable {
    let duration: CMTime
    let orientedPixelSize: CGSize
    let naturalSize: CGSize
    let preferredTransform: CGAffineTransform
    let nominalFrameRate: Float
    let isVFR: Bool
    let colorPrimaries: String?
    let transferFunction: String?
    let isHDR: Bool
    let videoCodec: String?
    let audioCodec: String?
    let hasAudio: Bool
    let audioChannelCount: Int

    /// A nil value means the pipeline should preserve source presentation timestamps.
    var recommendedFrameRate: Float? {
        nominalFrameRate > 0 && !isVFR ? nominalFrameRate : nil
    }

    static let unknown = VideoMetadata(
        duration: .invalid,
        orientedPixelSize: .zero,
        naturalSize: .zero,
        preferredTransform: .identity,
        nominalFrameRate: 0,
        isVFR: false,
        colorPrimaries: nil,
        transferFunction: nil,
        isHDR: false,
        videoCodec: nil,
        audioCodec: nil,
        hasAudio: false,
        audioChannelCount: 0
    )
}
