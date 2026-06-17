import XCTest
@testable import CyclingDomain

final class GPSMetricsTests: XCTestCase {
    private func d(_ s: TimeInterval) -> Date { Date(timeIntervalSince1970: s) }

    func test_distanceBetweenTwoPoints() {
        // 纬度相差 0.001 度 ≈ 111.2 m
        let samples = [
            GPSSample(timestamp: d(0), latitude: 0.000, longitude: 0, speedMps: 5),
            GPSSample(timestamp: d(10), latitude: 0.001, longitude: 0, speedMps: 5),
        ]
        let dist = totalDistanceMeters(samples)
        XCTAssertEqual(dist, 111.2, accuracy: 1.0)
    }

    func test_distanceWithFewerThanTwoSamplesIsZero() {
        XCTAssertEqual(totalDistanceMeters([]), 0)
        XCTAssertEqual(totalDistanceMeters([
            GPSSample(timestamp: d(0), latitude: 1, longitude: 1, speedMps: 5)
        ]), 0)
    }

    func test_averageSpeed() {
        // 1000 m / 100 s = 10 m/s
        XCTAssertEqual(averageSpeedMps(distanceMeters: 1000, duration: 100), 10, accuracy: 0.0001)
    }

    func test_averageSpeedZeroDurationIsZero() {
        XCTAssertEqual(averageSpeedMps(distanceMeters: 1000, duration: 0), 0)
    }
}
