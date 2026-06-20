import XCTest
@testable import CyclingDomain

final class RoutePropagationTests: XCTestCase {
    private func d(_ s: TimeInterval) -> Date { Date(timeIntervalSince1970: s) }

    /// 均速约 20km/h 的骑行 tracked，带两个采样点。
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

    func test_gpsTrackedRideCarriesRoute() {
        let rides = RideReconciler.reconcile(motionSegments: [], trackedRides: [trackedCycling(start: 0, durationSec: 300)])
        XCTAssertEqual(rides.count, 1)
        XCTAssertEqual(rides[0].route?.count, 2)
    }

    func test_motionOnlyRideHasNoRoute() {
        let motion = [MotionSegment(activityType: .walking, start: d(0), end: d(300), confidence: 1)]
        let rides = RideReconciler.reconcile(motionSegments: motion, trackedRides: [])
        XCTAssertNil(rides[0].route)
    }

    func test_withAvgHeartRatePreservesRoute() {
        let rides = RideReconciler.reconcile(motionSegments: [], trackedRides: [trackedCycling(start: 0, durationSec: 300)])
        let enriched = rides[0].withAvgHeartRate(140)
        XCTAssertEqual(enriched.avgHeartRate, 140)
        XCTAssertEqual(enriched.route?.count, 2)
    }
}
