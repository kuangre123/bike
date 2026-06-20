import XCTest
@testable import CyclingDomain

final class HeartRateDetectionTests: XCTestCase {
    private func t(_ s: TimeInterval) -> Date { Date(timeIntervalSince1970: s) }
    private func samples(_ pairs: [(TimeInterval, Double)]) -> [HeartRateSample] {
        pairs.map { HeartRateSample(timestamp: t($0.0), bpm: $0.1) }
    }

    func test_sustainedElevatedBecomesSegment() {
        // resting 60 → 阈值 max(100, 84)=100；7 个 110bpm 样本，跨 360s。
        let s = samples((0...6).map { (Double($0) * 60, 110.0) })
        let segs = detectElevatedHRSegments(from: s, restingBPM: 60, minDuration: 300, maxGap: 180)
        XCTAssertEqual(segs.count, 1)
        XCTAssertEqual(segs[0].start, t(0))
        XCTAssertEqual(segs[0].end, t(360))
        XCTAssertEqual(segs[0].avgBPM, 110, accuracy: 0.001)
    }

    func test_singleSpikeDropped() {
        let segs = detectElevatedHRSegments(from: samples([(0, 150)]), restingBPM: 60, minDuration: 300)
        XCTAssertTrue(segs.isEmpty)
    }

    func test_lowHRYieldsEmpty() {
        let s = samples((0...10).map { (Double($0) * 60, 80.0) }) // 低于 100 下限
        let segs = detectElevatedHRSegments(from: s, restingBPM: 60, minDuration: 300)
        XCTAssertTrue(segs.isEmpty)
    }

    func test_twoSeparateBoutsByLongGap() {
        var pairs: [(TimeInterval, Double)] = (0...5).map { (Double($0) * 60, 110.0) }   // 0..300
        pairs += (20...25).map { (Double($0) * 60, 110.0) }                              // 1200..1500
        let segs = detectElevatedHRSegments(from: samples(pairs), restingBPM: 60, minDuration: 300, maxGap: 180)
        XCTAssertEqual(segs.count, 2)
        XCTAssertEqual(segs[0].start, t(0));    XCTAssertEqual(segs[0].end, t(300))
        XCTAssertEqual(segs[1].start, t(1200)); XCTAssertEqual(segs[1].end, t(1500))
    }

    func test_thresholdUsesRestingMultiplierWhenHigher() {
        // resting 100 → 阈值 max(100, 140)=140；130bpm 不算升高。
        let s = samples((0...10).map { (Double($0) * 60, 130.0) })
        let segs = detectElevatedHRSegments(from: s, restingBPM: 100, multiplier: 1.4, absoluteFloor: 100, minDuration: 300)
        XCTAssertTrue(segs.isEmpty)
    }

    func test_hrOnlySegmentBecomesOtherWorkout() {
        let hr = [HRSegment(start: t(0), end: t(1800), avgBPM: 130)]
        let rides = RideReconciler.reconcile(motionSegments: [], trackedRides: [], heartRateSegments: hr)
        XCTAssertEqual(rides.count, 1)
        XCTAssertEqual(rides[0].activityType, .other)
        XCTAssertEqual(rides[0].source, .heartRateOnly)
        XCTAssertEqual(rides[0].avgHeartRate, 130)
        XCTAssertNotNil(rides[0].calories)
    }

    func test_hrOverlappingMotionEnrichesNotDuplicates() {
        let motion = [MotionSegment(activityType: .running, start: t(0), end: t(1800), confidence: 2)]
        let hr = [HRSegment(start: t(60), end: t(1740), avgBPM: 150)]
        let rides = RideReconciler.reconcile(motionSegments: motion, trackedRides: [], heartRateSegments: hr)
        XCTAssertEqual(rides.count, 1) // 不重复建记录
        XCTAssertEqual(rides[0].activityType, .running)
        XCTAssertEqual(rides[0].avgHeartRate, 150) // 被增强
    }
}
