import XCTest
@testable import CyclingDomain

final class SegmentMergingTests: XCTestCase {
    private func d(_ s: TimeInterval) -> Date { Date(timeIntervalSince1970: s) }

    func test_mergesSameTypeWithinGap() {
        let segs = [
            MotionSegment(activityType: .cycling, start: d(0), end: d(120), confidence: 2),
            MotionSegment(activityType: .cycling, start: d(140), end: d(300), confidence: 2),
        ]
        let merged = mergeActivitySegments(segs, maxGap: 60, minDuration: 90)
        XCTAssertEqual(merged.count, 1)
        XCTAssertEqual(merged[0].start, d(0))
        XCTAssertEqual(merged[0].end, d(300))
    }

    func test_differentTypesDoNotMerge() {
        let segs = [
            MotionSegment(activityType: .walking, start: d(0), end: d(120), confidence: 2),
            MotionSegment(activityType: .cycling, start: d(130), end: d(300), confidence: 2),
        ]
        let merged = mergeActivitySegments(segs, maxGap: 60, minDuration: 90)
        XCTAssertEqual(merged.count, 2)
    }

    func test_keepsSegmentsApartBeyondGap() {
        let segs = [
            MotionSegment(activityType: .cycling, start: d(0), end: d(120), confidence: 2),
            MotionSegment(activityType: .cycling, start: d(1000), end: d(1200), confidence: 2),
        ]
        let merged = mergeActivitySegments(segs, maxGap: 60, minDuration: 90)
        XCTAssertEqual(merged.count, 2)
    }

    func test_dropsTooShortSegments() {
        let segs = [
            MotionSegment(activityType: .running, start: d(0), end: d(30), confidence: 2),
        ]
        let merged = mergeActivitySegments(segs, maxGap: 60, minDuration: 90)
        XCTAssertTrue(merged.isEmpty)
    }

    func test_mergedConfidenceIsMax() {
        let segs = [
            MotionSegment(activityType: .cycling, start: d(0), end: d(120), confidence: 1),
            MotionSegment(activityType: .cycling, start: d(130), end: d(300), confidence: 2),
        ]
        let merged = mergeActivitySegments(segs, maxGap: 60, minDuration: 90)
        XCTAssertEqual(merged[0].confidence, 2)
    }
}
