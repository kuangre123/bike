import XCTest
@testable import CyclingDomain

final class RideReconcilerTests: XCTestCase {
    private func d(_ s: TimeInterval) -> Date { Date(timeIntervalSince1970: s) }

    /// 构造一条均速约 20km/h、时长 durationSec 秒的骑行 tracked。
    private func trackedCycling(start: TimeInterval, durationSec: TimeInterval) -> TrackedRide {
        let meters = 5.556 * durationSec
        let dLat = meters / 111_320.0
        return TrackedRide(
            activityType: .cycling,
            start: d(start), end: d(start + durationSec),
            samples: [
                GPSSample(timestamp: d(start), latitude: 0, longitude: 0, speedMps: 5.556),
                GPSSample(timestamp: d(start + durationSec), latitude: dLat, longitude: 0, speedMps: 5.556),
            ]
        )
    }

    func test_overlappingSameTypeBecomesMerged() {
        let motion = [MotionSegment(activityType: .cycling, start: d(0), end: d(600), confidence: 2)]
        let rides = RideReconciler.reconcile(motionSegments: motion, trackedRides: [trackedCycling(start: 60, durationSec: 480)])
        XCTAssertEqual(rides.count, 1)
        XCTAssertEqual(rides[0].source, .merged)
        XCTAssertEqual(rides[0].activityType, .cycling)
        XCTAssertNotNil(rides[0].distanceMeters)
        XCTAssertNotNil(rides[0].calories)
    }

    func test_overlappingDifferentTypeDoesNotMerge() {
        // 步行 motion 与 骑行 tracked 时间重叠但类型不同 → 不合并：各自成段
        let motion = [MotionSegment(activityType: .walking, start: d(0), end: d(600), confidence: 2)]
        let rides = RideReconciler.reconcile(motionSegments: motion, trackedRides: [trackedCycling(start: 60, durationSec: 480)])
        XCTAssertEqual(rides.count, 2)
        XCTAssertEqual(Set(rides.map { $0.source }), [.gpsTracked, .motionOnly])
        XCTAssertEqual(Set(rides.map { $0.activityType }), [.walking, .cycling])
    }

    func test_motionWithoutTrackedIsMotionOnly() {
        let motion = [MotionSegment(activityType: .walking, start: d(0), end: d(300), confidence: 1)]
        let rides = RideReconciler.reconcile(motionSegments: motion, trackedRides: [])
        XCTAssertEqual(rides.count, 1)
        XCTAssertEqual(rides[0].source, .motionOnly)
        XCTAssertEqual(rides[0].activityType, .walking)
        XCTAssertNil(rides[0].distanceMeters)
        XCTAssertEqual(rides[0].confidence, 1)
    }

    func test_trackedWithoutMotionIsGpsTracked() {
        let rides = RideReconciler.reconcile(motionSegments: [], trackedRides: [trackedCycling(start: 0, durationSec: 300)])
        XCTAssertEqual(rides.count, 1)
        XCTAssertEqual(rides[0].source, .gpsTracked)
        XCTAssertNotNil(rides[0].distanceMeters)
    }

    func test_implausibleSpeedTrackedIsDropped() {
        // 约 120 km/h 的「骑行」→ 速度不合理 → 丢弃
        let fast = TrackedRide(
            activityType: .cycling,
            start: d(0), end: d(100),
            samples: [
                GPSSample(timestamp: d(0), latitude: 0, longitude: 0, speedMps: 33),
                GPSSample(timestamp: d(100), latitude: (33.3 * 100) / 111_320.0, longitude: 0, speedMps: 33),
            ]
        )
        let rides = RideReconciler.reconcile(motionSegments: [], trackedRides: [fast])
        XCTAssertTrue(rides.isEmpty)
    }

    func test_resultSortedByStart() {
        let motion = [
            MotionSegment(activityType: .running, start: d(1000), end: d(1300), confidence: 1),
            MotionSegment(activityType: .walking, start: d(0), end: d(300), confidence: 1),
        ]
        let rides = RideReconciler.reconcile(motionSegments: motion, trackedRides: [])
        XCTAssertEqual(rides.map { $0.start }, [d(0), d(1000)])
    }
}
