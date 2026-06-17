import XCTest
@testable import CyclingDomain

final class RideReconcilerTests: XCTestCase {
    private func d(_ s: TimeInterval) -> Date { Date(timeIntervalSince1970: s) }

    /// 构造一条均速约 20km/h、时长 durationSec 秒的 tracked（两点拉开足够距离）。
    private func tracked(start: TimeInterval, durationSec: TimeInterval) -> TrackedRide {
        // 20 km/h ≈ 5.556 m/s；距离 = 5.556 * durationSec
        // 用纬度位移制造距离：1 度纬度 ≈ 111_320 m
        let meters = 5.556 * durationSec
        let dLat = meters / 111_320.0
        return TrackedRide(
            start: d(start), end: d(start + durationSec),
            samples: [
                GPSSample(timestamp: d(start), latitude: 0, longitude: 0, speedMps: 5.556),
                GPSSample(timestamp: d(start + durationSec), latitude: dLat, longitude: 0, speedMps: 5.556),
            ]
        )
    }

    func test_overlappingMotionAndTrackedBecomesMerged() {
        let motion = [MotionSegment(start: d(0), end: d(600), confidence: 2)]
        let rides = RideReconciler.reconcile(motionSegments: motion, trackedRides: [tracked(start: 60, durationSec: 480)])
        XCTAssertEqual(rides.count, 1)
        XCTAssertEqual(rides[0].source, .merged)
        XCTAssertNotNil(rides[0].distanceMeters)
        XCTAssertNotNil(rides[0].calories)
    }

    func test_motionWithoutTrackedIsMotionOnly() {
        let motion = [MotionSegment(start: d(0), end: d(300), confidence: 1)]
        let rides = RideReconciler.reconcile(motionSegments: motion, trackedRides: [])
        XCTAssertEqual(rides.count, 1)
        XCTAssertEqual(rides[0].source, .motionOnly)
        XCTAssertNil(rides[0].distanceMeters)
        XCTAssertNil(rides[0].calories)
        XCTAssertEqual(rides[0].confidence, 1)
    }

    func test_trackedWithoutMotionIsGpsTracked() {
        let rides = RideReconciler.reconcile(motionSegments: [], trackedRides: [tracked(start: 0, durationSec: 300)])
        XCTAssertEqual(rides.count, 1)
        XCTAssertEqual(rides[0].source, .gpsTracked)
        XCTAssertNotNil(rides[0].distanceMeters)
    }

    func test_implausibleSpeedTrackedIsDropped() {
        // 制造一个超快 tracked：约 120 km/h
        let fast = TrackedRide(
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
            MotionSegment(start: d(1000), end: d(1300), confidence: 1),
            MotionSegment(start: d(0),    end: d(300),  confidence: 1),
        ]
        let rides = RideReconciler.reconcile(motionSegments: motion, trackedRides: [])
        XCTAssertEqual(rides.map { $0.start }, [d(0), d(1000)])
    }
}
