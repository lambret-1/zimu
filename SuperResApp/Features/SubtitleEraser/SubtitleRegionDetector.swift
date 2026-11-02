import CoreGraphics
import Foundation
import ImageIO
import Vision

/// On-device subtitle text detector. Vision coordinates are converted to top-left normalized coordinates.
struct SubtitleRegionDetector {
    var minimumConfidence: Double = 0.6
    var bottomRegionFraction: Double = 0.35
    var horizontalMergeGap: Double = 0.025
    var verticalMergeGap: Double = 0.015

    func detect(
        cgImage: CGImage,
        orientation: CGImagePropertyOrientation = .up
    ) throws -> [DetectedSubtitleRegion] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = false
        request.minimumTextHeight = 0.008
        request.recognitionLanguages = ["zh-Hans", "en-US"]

        let handler = VNImageRequestHandler(cgImage: cgImage, orientation: orientation, options: [:])
        try handler.perform([request])

        let candidates = (request.results ?? []).compactMap { observation -> DetectedSubtitleRegion? in
            guard let text = observation.topCandidates(1).first,
                  let rect = Self.normalizedRect(fromVisionBoundingBox: observation.boundingBox) else {
                return nil
            }
            return DetectedSubtitleRegion(
                rect: rect,
                confidence: Double(text.confidence),
                source: .vision
            )
        }
        return Self.filterAndMerge(
            candidates,
            minimumConfidence: minimumConfidence,
            bottomRegionFraction: bottomRegionFraction,
            horizontalMergeGap: horizontalMergeGap,
            verticalMergeGap: verticalMergeGap
        )
    }

    /// Vision uses a bottom-left origin; app masks use a top-left origin.
    static func normalizedRect(fromVisionBoundingBox box: CGRect) -> NormalizedRect? {
        guard box.origin.x.isFinite, box.origin.y.isFinite,
              box.width.isFinite, box.height.isFinite,
              box.width > 0, box.height > 0 else { return nil }
        let minX = max(0, min(1, box.minX))
        let maxX = max(0, min(1, box.maxX))
        let minVisionY = max(0, min(1, box.minY))
        let maxVisionY = max(0, min(1, box.maxY))
        guard maxX > minX, maxVisionY > minVisionY else { return nil }
        return NormalizedRect(
            origin: NormalizedPoint(x: minX, y: 1 - maxVisionY),
            width: maxX - minX,
            height: maxVisionY - minVisionY
        )
    }

    /// Filters out low-confidence and non-bottom text, then merges nearby word boxes transitively.
    static func filterAndMerge(
        _ candidates: [DetectedSubtitleRegion],
        minimumConfidence: Double = 0.6,
        bottomRegionFraction: Double = 0.35,
        horizontalMergeGap: Double = 0.025,
        verticalMergeGap: Double = 0.015
    ) -> [DetectedSubtitleRegion] {
        let safeBottomFraction = min(max(bottomRegionFraction, 0), 1)
        var merged: [DetectedSubtitleRegion] = []

        let valid = candidates.filter { candidate in
            let rect = candidate.rect
            return candidate.confidence.isFinite
                && candidate.confidence >= minimumConfidence
                && rect.origin.x.isFinite && rect.origin.y.isFinite
                && rect.width.isFinite && rect.height.isFinite
                && rect.width > 0 && rect.height > 0
                && rect.maxX <= 1 && rect.maxY <= 1
                && rect.origin.y + rect.height / 2 >= 1 - safeBottomFraction
        }.sorted {
            if $0.rect.origin.y == $1.rect.origin.y {
                return $0.rect.origin.x < $1.rect.origin.x
            }
            return $0.rect.origin.y < $1.rect.origin.y
        }

        for candidate in valid {
            var combined = candidate
            var didMerge = true
            while didMerge {
                didMerge = false
                var index = 0
                while index < merged.count {
                    if shouldMerge(
                        merged[index].rect,
                        combined.rect,
                        horizontalGap: max(0, horizontalMergeGap),
                        verticalGap: max(0, verticalMergeGap)
                    ) {
                        combined = union(merged[index], combined)
                        merged.remove(at: index)
                        didMerge = true
                        index = 0
                    } else {
                        index += 1
                    }
                }
            }
            merged.append(combined)
        }

        return merged.sorted {
            if $0.rect.origin.y == $1.rect.origin.y {
                return $0.rect.origin.x < $1.rect.origin.x
            }
            return $0.rect.origin.y < $1.rect.origin.y
        }
    }

    private static func shouldMerge(
        _ lhs: NormalizedRect,
        _ rhs: NormalizedRect,
        horizontalGap: Double,
        verticalGap: Double
    ) -> Bool {
        let xOverlap = min(lhs.maxX, rhs.maxX) - max(lhs.origin.x, rhs.origin.x)
        let yOverlap = min(lhs.maxY, rhs.maxY) - max(lhs.origin.y, rhs.origin.y)
        let gapX = max(0, max(lhs.origin.x, rhs.origin.x) - min(lhs.maxX, rhs.maxX))
        let gapY = max(0, max(lhs.origin.y, rhs.origin.y) - min(lhs.maxY, rhs.maxY))
        return (yOverlap > 0 && gapX <= horizontalGap)
            || (xOverlap > 0 && gapY <= verticalGap)
    }

    private static func union(
        _ lhs: DetectedSubtitleRegion,
        _ rhs: DetectedSubtitleRegion
    ) -> DetectedSubtitleRegion {
        let minX = min(lhs.rect.origin.x, rhs.rect.origin.x)
        let minY = min(lhs.rect.origin.y, rhs.rect.origin.y)
        let maxX = max(lhs.rect.maxX, rhs.rect.maxX)
        let maxY = max(lhs.rect.maxY, rhs.rect.maxY)
        return DetectedSubtitleRegion(
            rect: NormalizedRect(
                origin: NormalizedPoint(x: minX, y: minY),
                width: maxX - minX,
                height: maxY - minY
            ),
            confidence: max(lhs.confidence, rhs.confidence),
            source: lhs.source == rhs.source ? lhs.source : .vision
        )
    }
}
