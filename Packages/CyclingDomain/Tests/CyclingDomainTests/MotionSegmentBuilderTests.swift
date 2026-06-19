import XCTest
@testable import CyclingDomain

final class MotionSegmentBuilderTests: XCTestCase {
    private func d(_ s: TimeInterval) -> Date { Date(timeIntervalSince1970: s) }

    func test_singleRunClosedByNonCycling() {
        let segs = buildCyclingSegments(from: [
            RawActivitySample(start: d(0), isCycling: true, confidence: 2),
            RawActivitySample(start: d(120), isCycling: false, confidence: 0),
        ], queryEnd: d(200))
        XCTAssertEqual(segs, [MotionSegment(start: d(0), end: d(120), confidence: 2)])
    }

    func test_runContinuesToQueryEnd() {
        let segs = buildCyclingSegments(from: [
            RawActivitySample(start: d(0), isCycling: true, confidence: 1),
        ], queryEnd: d(300))
        XCTAssertEqual(segs, [MotionSegment(start: d(0), end: d(300), confidence: 1)])
    }

    func test_confidenceIsMaxAcrossRun() {
        let segs = buildCyclingSegments(from: [
            RawActivitySample(start: d(0), isCycling: true, confidence: 1),
            RawActivitySample(start: d(60), isCycling: true, confidence: 2),
            RawActivitySample(start: d(120), isCycling: false, confidence: 0),
        ], queryEnd: d(200))
        XCTAssertEqual(segs, [MotionSegment(start: d(0), end: d(120), confidence: 2)])
    }

    func test_twoSeparateRuns() {
        let segs = buildCyclingSegments(from: [
            RawActivitySample(start: d(0), isCycling: true, confidence: 2),
            RawActivitySample(start: d(60), isCycling: false, confidence: 0),
            RawActivitySample(start: d(600), isCycling: true, confidence: 1),
            RawActivitySample(start: d(660), isCycling: false, confidence: 0),
        ], queryEnd: d(700))
        XCTAssertEqual(segs, [
            MotionSegment(start: d(0), end: d(60), confidence: 2),
            MotionSegment(start: d(600), end: d(660), confidence: 1),
        ])
    }

    func test_noCyclingYieldsEmpty() {
        let segs = buildCyclingSegments(from: [
            RawActivitySample(start: d(0), isCycling: false, confidence: 0),
        ], queryEnd: d(100))
        XCTAssertTrue(segs.isEmpty)
    }

    func test_unsortedInputHandled() {
        let segs = buildCyclingSegments(from: [
            RawActivitySample(start: d(120), isCycling: false, confidence: 0),
            RawActivitySample(start: d(0), isCycling: true, confidence: 2),
        ], queryEnd: d(200))
        XCTAssertEqual(segs, [MotionSegment(start: d(0), end: d(120), confidence: 2)])
    }
}
