import XCTest
@testable import CyclingDomain

final class MotionSegmentBuilderTests: XCTestCase {
    private func d(_ s: TimeInterval) -> Date { Date(timeIntervalSince1970: s) }

    func test_singleRunClosedByNonActivity() {
        let segs = buildActivitySegments(from: [
            RawActivitySample(start: d(0), activity: .cycling, confidence: 2),
            RawActivitySample(start: d(120), activity: nil, confidence: 0),
        ], queryEnd: d(200))
        XCTAssertEqual(segs, [MotionSegment(activityType: .cycling, start: d(0), end: d(120), confidence: 2)])
    }

    func test_runContinuesToQueryEnd() {
        let segs = buildActivitySegments(from: [
            RawActivitySample(start: d(0), activity: .running, confidence: 1),
        ], queryEnd: d(300))
        XCTAssertEqual(segs, [MotionSegment(activityType: .running, start: d(0), end: d(300), confidence: 1)])
    }

    func test_typeChangeSplitsSegments() {
        let segs = buildActivitySegments(from: [
            RawActivitySample(start: d(0), activity: .walking, confidence: 2),
            RawActivitySample(start: d(60), activity: .cycling, confidence: 2),
            RawActivitySample(start: d(120), activity: nil, confidence: 0),
        ], queryEnd: d(200))
        XCTAssertEqual(segs, [
            MotionSegment(activityType: .walking, start: d(0), end: d(60), confidence: 2),
            MotionSegment(activityType: .cycling, start: d(60), end: d(120), confidence: 2),
        ])
    }

    func test_confidenceIsMaxAcrossRun() {
        let segs = buildActivitySegments(from: [
            RawActivitySample(start: d(0), activity: .cycling, confidence: 1),
            RawActivitySample(start: d(60), activity: .cycling, confidence: 2),
            RawActivitySample(start: d(120), activity: nil, confidence: 0),
        ], queryEnd: d(200))
        XCTAssertEqual(segs, [MotionSegment(activityType: .cycling, start: d(0), end: d(120), confidence: 2)])
    }

    func test_noActivityYieldsEmpty() {
        let segs = buildActivitySegments(from: [
            RawActivitySample(start: d(0), activity: nil, confidence: 0),
        ], queryEnd: d(100))
        XCTAssertTrue(segs.isEmpty)
    }

    func test_unsortedInputHandled() {
        let segs = buildActivitySegments(from: [
            RawActivitySample(start: d(120), activity: nil, confidence: 0),
            RawActivitySample(start: d(0), activity: .cycling, confidence: 2),
        ], queryEnd: d(200))
        XCTAssertEqual(segs, [MotionSegment(activityType: .cycling, start: d(0), end: d(120), confidence: 2)])
    }
}
