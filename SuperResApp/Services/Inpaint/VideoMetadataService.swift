import AVFoundation
import CoreMedia
import Foundation

enum VideoMetadataService {
    private struct ColorInfo {
        let primaries: String?
        let transfer: String?
        let isHDR: Bool
    }

    private struct AudioInfo {
        let codec: String?
        let channels: Int
    }

    enum ReadError: LocalizedError {
        case noVideoTrack
        case loadFailed(String)

        var errorDescription: String? {
            switch self {
            case .noVideoTrack:
                return "视频不包含视频轨"
            case .loadFailed(let message):
                return "视频元数据读取失败：\(message)"
            }
        }
    }

    /// Reads track metadata without decoding video pixels.
    static func read(asset: AVAsset) async throws -> VideoMetadata {
        let videoTracks: [AVAssetTrack]
        let audioTracks: [AVAssetTrack]
        do {
            videoTracks = try await asset.loadTracks(withMediaType: .video)
            audioTracks = try await asset.loadTracks(withMediaType: .audio)
        } catch {
            throw ReadError.loadFailed(error.localizedDescription)
        }

        guard let videoTrack = videoTracks.first else {
            throw ReadError.noVideoTrack
        }

        async let durationValue = asset.load(.duration)
        async let naturalSizeValue = videoTrack.load(.naturalSize)
        async let transformValue = videoTrack.load(.preferredTransform)
        async let frameRateValue = videoTrack.load(.nominalFrameRate)
        async let formatsValue = videoTrack.load(.formatDescriptions)

        let duration = (try? await durationValue) ?? .invalid
        let naturalSize = (try? await naturalSizeValue) ?? .zero
        let transform = (try? await transformValue) ?? .identity
        let frameRate = (try? await frameRateValue) ?? 0
        let formats = (try? await formatsValue) ?? []

        let colorInfo = inspectColor(formats: formats)
        let videoCodec = firstFourCC(from: formats)
        let audioInfo = await inspectAudio(track: audioTracks.first)
        let isVFR = await detectVFR(asset: asset, track: videoTrack)

        return VideoMetadata(
            duration: duration,
            orientedPixelSize: orientedSize(naturalSize: naturalSize, transform: transform),
            naturalSize: naturalSize,
            preferredTransform: transform,
            nominalFrameRate: frameRate,
            isVFR: isVFR,
            colorPrimaries: colorInfo.primaries,
            transferFunction: colorInfo.transfer,
            isHDR: colorInfo.isHDR,
            videoCodec: videoCodec,
            audioCodec: audioInfo.codec,
            hasAudio: audioInfo.codec != nil,
            audioChannelCount: audioInfo.channels
        )
    }

    private static func inspectColor(formats: [CMFormatDescription]) -> ColorInfo {
        guard let format = formats.first else {
            return ColorInfo(primaries: nil, transfer: nil, isHDR: false)
        }

        let primaries = CMFormatDescriptionGetExtension(
            format,
            extensionKey: kCMFormatDescriptionExtension_ColorPrimaries
        ) as? String
        let transfer = CMFormatDescriptionGetExtension(
            format,
            extensionKey: kCMFormatDescriptionExtension_TransferFunction
        ) as? String

        let isWideGamutHDR = primaries?.contains("2020") == true
        let isHDRTransfer = transfer?.contains("PQ") == true || transfer?.contains("HLG") == true
        return ColorInfo(
            primaries: primaries,
            transfer: transfer,
            isHDR: isWideGamutHDR || isHDRTransfer
        )
    }

    private static func firstFourCC(from formats: [CMFormatDescription]) -> String? {
        guard let format = formats.first else {
            return nil
        }
        return fourCCString(CMFormatDescriptionGetMediaSubType(format))
    }

    private static func fourCCString(_ code: FourCharCode) -> String {
        let scalars = [
            (code >> 24) & 0xFF,
            (code >> 16) & 0xFF,
            (code >> 8) & 0xFF,
            code & 0xFF
        ]
        return String(scalars.map { Character(UnicodeScalar($0) ?? "?") })
    }

    private static func inspectAudio(track: AVAssetTrack?) async -> AudioInfo {
        guard let track else {
            return AudioInfo(codec: nil, channels: 0)
        }
        let formats = (try? await track.load(.formatDescriptions)) ?? []
        guard let format = formats.first else {
            return AudioInfo(codec: nil, channels: 0)
        }

        let codec = fourCCString(CMFormatDescriptionGetMediaSubType(format))
        let streamDescription = CMAudioFormatDescriptionGetStreamBasicDescription(format)
        let channels = streamDescription.map { Int($0.pointee.mChannelsPerFrame) } ?? 0
        return AudioInfo(codec: codec, channels: channels)
    }

    /// Applies the track transform to obtain the display-oriented pixel dimensions.
    static func orientedSize(naturalSize: CGSize, transform: CGAffineTransform) -> CGSize {
        let width = abs(naturalSize.width * transform.a + naturalSize.height * transform.c)
        let height = abs(naturalSize.width * transform.b + naturalSize.height * transform.d)
        let result = CGSize(width: round(width), height: round(height))
        return result.width > 0 && result.height > 0 ? result : naturalSize
    }

    private static func detectVFR(asset: AVAsset, track: AVAssetTrack) async -> Bool {
        guard let reader = try? AVAssetReader(asset: asset) else {
            return false
        }
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: nil)
        guard reader.canAdd(output) else {
            return false
        }
        reader.add(output)
        guard reader.startReading() else {
            return false
        }
        defer { reader.cancelReading() }

        var intervals: [Double] = []
        var lastPTS: CMTime?
        var sampleCount = 0
        while sampleCount < 30, let sample = output.copyNextSampleBuffer() {
            let pts = CMSampleBufferGetPresentationTimeStamp(sample)
            if let lastPTS, pts.isValid, lastPTS.isValid {
                let delta = (pts - lastPTS).seconds
                if delta > 0 {
                    intervals.append(delta)
                }
            }
            lastPTS = pts
            sampleCount += 1
        }
        return isVFR(fromIntervals: intervals)
    }

    /// Classifies sampled PTS intervals using the coefficient of variation.
    static func isVFR(fromIntervals intervals: [Double]) -> Bool {
        guard intervals.count >= 5 else {
            return false
        }
        let mean = intervals.reduce(0, +) / Double(intervals.count)
        guard mean > 0 else {
            return false
        }
        let variance = intervals
            .map { ($0 - mean) * ($0 - mean) }
            .reduce(0, +) / Double(intervals.count)
        return variance.squareRoot() / mean > 0.1
    }
}
