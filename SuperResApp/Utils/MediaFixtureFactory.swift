#if DEBUG
import AVFoundation
import CoreGraphics
import CoreVideo
import Foundation
import UIKit

/// Creates small deterministic video fixtures for simulator tests.
enum MediaFixtureFactory {
    static func makeTestVideo(
        duration: TimeInterval = 1,
        size: CGSize = CGSize(width: 320, height: 240),
        fps: Int = 30
    ) throws -> URL {
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("subtitle-fixture-\(UUID().uuidString).mp4")
        let writer = try AVAssetWriter(outputURL: outputURL, fileType: .mp4)
        let settings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: Int(size.width),
            AVVideoHeightKey: Int(size.height)
        ]
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
        input.expectsMediaDataInRealTime = false
        let attributes: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: Int(size.width),
            kCVPixelBufferHeightKey as String: Int(size.height)
        ]
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: attributes
        )

        guard writer.canAdd(input) else {
            throw fixtureError("无法添加视频输入")
        }
        writer.add(input)
        guard writer.startWriting() else {
            throw writer.error ?? fixtureError("无法启动视频写入")
        }
        writer.startSession(atSourceTime: .zero)

        let frameCount = max(1, Int(duration * Double(fps)))
        for index in 0..<frameCount {
            while !input.isReadyForMoreMediaData {
                if writer.status == .failed || writer.status == .cancelled {
                    throw writer.error ?? fixtureError("视频写入中断")
                }
                Thread.sleep(forTimeInterval: 0.001)
            }
            guard let pool = adaptor.pixelBufferPool else {
                throw fixtureError("无法创建像素缓冲池")
            }
            var pixelBuffer: CVPixelBuffer?
            let status = CVPixelBufferPoolCreatePixelBuffer(nil, pool, &pixelBuffer)
            guard status == kCVReturnSuccess, let pixelBuffer else {
                throw fixtureError("无法分配像素缓冲")
            }
            fill(buffer: pixelBuffer, color: .systemTeal)
            let timestamp = CMTime(value: CMTimeValue(index), timescale: CMTimeScale(fps))
            guard adaptor.append(pixelBuffer, withPresentationTime: timestamp) else {
                throw writer.error ?? fixtureError("视频帧写入失败")
            }
        }

        input.markAsFinished()
        let finished = DispatchSemaphore(value: 0)
        writer.finishWriting {
            finished.signal()
        }
        guard finished.wait(timeout: .now() + 10) == .success else {
            writer.cancelWriting()
            throw fixtureError("等待视频写入超时")
        }
        guard writer.status == .completed else {
            throw writer.error ?? fixtureError("视频文件生成失败")
        }
        return outputURL
    }

    private static func fill(buffer: CVPixelBuffer, color: UIColor) {
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        guard let baseAddress = CVPixelBufferGetBaseAddress(buffer) else {
            return
        }

        let width = CVPixelBufferGetWidth(buffer)
        let height = CVPixelBufferGetHeight(buffer)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(buffer)
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        color.getRed(&red, green: &green, blue: &blue, alpha: &alpha)

        let pixels = baseAddress.assumingMemoryBound(to: UInt8.self)
        for rowIndex in 0..<height {
            let row = pixels.advanced(by: rowIndex * bytesPerRow)
            for columnIndex in 0..<width {
                let pixel = row.advanced(by: columnIndex * 4)
                pixel[0] = UInt8(blue * 255)
                pixel[1] = UInt8(green * 255)
                pixel[2] = UInt8(red * 255)
                pixel[3] = UInt8(alpha * 255)
            }
        }
    }

    private static func fixtureError(_ message: String) -> NSError {
        NSError(
            domain: "MediaFixtureFactory",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: message]
        )
    }
}
#endif
