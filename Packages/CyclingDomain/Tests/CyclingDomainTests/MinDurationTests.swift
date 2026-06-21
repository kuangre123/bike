import XCTest
@testable import CyclingDomain

final class MinDurationTests: XCTestCase {
    private func d(_ s: TimeInterval) -> Date { Date(timeIntervalSince1970: s) }

    func test_walkingShorterThanFiveMinutesDropped() {
        let segs = [
            MotionSegment(activityType: .walking, start: d(0), end: d(180), confidence: 2),     // 3 分钟
            MotionSegment(activityType: .cycling, start: d(1000), end: d(1180), confidence: 2), // 3 分钟
        ]
        let merged = mergeActivitySegments(
            segs, maxGap: 60, minDuration: 120,
            minDurationForType: RideDetectionPolicy.minimumDuration(for:)
        )
        // 步行 3 分钟 < 5 分钟 → 丢；骑行 3 分钟 >= 2 分钟 → 留
        XCTAssertEqual(merged.map(\.activityType), [.cycling])
    }

    func test_walkingOverFiveMinutesKept() {
        let segs = [MotionSegment(activityType: .walking, start: d(0), end: d(360), confidence: 2)] // 6 分钟
        let merged = mergeActivitySegments(
            segs, maxGap: 60, minDuration: 120,
            minDurationForType: RideDetectionPolicy.minimumDuration(for:)
        )
        XCTAssertEqual(merged.count, 1)
    }

    func test_policyMinimums() {
        XCTAssertEqual(RideDetectionPolicy.minimumDuration(for: .walking), 300)
        XCTAssertEqual(RideDetectionPolicy.minimumDuration(for: .cycling), 120)
        XCTAssertEqual(RideDetectionPolicy.minimumDuration(for: .running), 120)
    }
}
