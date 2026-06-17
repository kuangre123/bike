import XCTest
@testable import CyclingDomain

final class CalorieEstimatorTests: XCTestCase {
    func test_metsBuckets() {
        XCTAssertEqual(cyclingMETs(avgSpeedMps: 14 / 3.6), 4.0)  // <16
        XCTAssertEqual(cyclingMETs(avgSpeedMps: 18 / 3.6), 6.0)  // 16–19
        XCTAssertEqual(cyclingMETs(avgSpeedMps: 21 / 3.6), 8.0)  // 19–22
        XCTAssertEqual(cyclingMETs(avgSpeedMps: 24 / 3.6), 10.0) // 22–25
        XCTAssertEqual(cyclingMETs(avgSpeedMps: 30 / 3.6), 12.0) // >=25
    }

    func test_caloriesKnownCase() {
        // 20 km/h 落在 19–22 档 → 8 METs；8 × 70kg × 1h = 560 kcal
        let kcal = estimateCalories(avgSpeedMps: 20 / 3.6, duration: 3600, weightKg: 70)
        XCTAssertEqual(kcal, 560, accuracy: 0.001)
    }

    func test_caloriesScalesWithDuration() {
        let half = estimateCalories(avgSpeedMps: 20 / 3.6, duration: 1800, weightKg: 70)
        XCTAssertEqual(half, 280, accuracy: 0.001)
    }
}
