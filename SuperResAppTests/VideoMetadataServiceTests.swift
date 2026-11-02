import AVFoundation
import CoreGraphics
import XCTest
@testable import SuperResApp

final class VideoMetadataServiceTests: XCTestCase {
    func testIsVFRStableIntervals() {
        let intervals = Array(repeating: 1.0 / 30.0, count: 30)
        XCTAssertFalse(VideoMetadataService.isVFR(fromIntervals: intervals))
    }

    func testIsVFRUnstableIntervals() {
        let intervals = (0..<30).map { $0.isMultiple(of: 2) ? 1.0 / 60.0 : 1.0 / 15.0 }
        XCTAssertTrue(VideoMetadataService.isVFR(fromIntervals: intervals))
    }

    func testIsVFRTooFewSamples() {
        XCTAssertFalse(VideoMetadataService.isVFR(fromIntervals: [0.03, 0.03]))
    }

    func testOrientedSizeIdentity() {
        let size = VideoMetadataService.orientedSize(
            naturalSize: CGSize(width: 1920, height: 1080),
            transform: .identity
        )
        XCTAssertEqual(size, CGSize(width: 1920, height: 1080))
    }

    func testOrientedSizeRotated90() {
        let size = VideoMetadataService.orientedSize(
            naturalSize: CGSize(width: 1920, height: 1080),
            transform: CGAffineTransform(rotationAngle: .pi / 2)
        )
        XCTAssertEqual(size.width, 1080, accuracy: 0.5)
        XCTAssertEqual(size.height, 1920, accuracy: 0.5)
    }

    func testReadSyntheticVideo() async throws {
        let url = try MediaFixtureFactory.makeTestVideo()
        defer { try? FileManager.default.removeItem(at: url) }

        let metadata = try await VideoMetadataService.read(asset: AVURLAsset(url: url))
        XCTAssertEqual(metadata.orientedPixelSize.width, 320, accuracy: 1)
        XCTAssertEqual(metadata.orientedPixelSize.height, 240, accuracy: 1)
        XCTAssertEqual(metadata.nominalFrameRate, 30, accuracy: 1)
        XCTAssertFalse(metadata.isVFR)
        XCTAssertFalse(metadata.isHDR)
        XCTAssertFalse(metadata.hasAudio)
        XCTAssertEqual(metadata.duration.seconds, 1, accuracy: 0.1)
        XCTAssertEqual(metadata.videoCodec, "avc1")
    }
}
