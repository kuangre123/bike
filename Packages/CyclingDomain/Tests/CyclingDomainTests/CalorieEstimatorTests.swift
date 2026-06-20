import XCTest
@testable import CyclingDomain

final class CalorieEstimatorTests: XCTestCase {
    func test_cyclingMETsBuckets() {
        XCTAssertEqual(metsFor(.cycling, avgSpeedMps: 14 / 3.6), 4.0)
        XCTAssertEqual(metsFor(.cycling, avgSpeedMps: 21 / 3.6), 8.0)
        XCTAssertEqual(metsFor(.cycling, avgSpeedMps: 30 / 3.6), 12.0)
    }

    func test_runningAndWalkingMETs() {
        XCTAssertEqual(metsFor(.running, avgSpeedMps: 10 / 3.6), 10.0) // <11
        XCTAssertEqual(metsFor(.walking, avgSpeedMps: 5 / 3.6), 3.5)   // <5.5
    }

    func test_cyclingCaloriesKnownCase() {
        // 20 km/h 落在 19–22 档 → 8 METs；8 × 70kg × 1h = 560 kcal
        let kcal = estimateCalories(for: .cycling, avgSpeedMps: 20 / 3.6, duration: 3600, weightKg: 70)
        XCTAssertEqual(kcal, 560, accuracy: 0.001)
    }

    func test_runningCaloriesKnownCase() {
        // 10 km/h → 10 METs；10 × 70 × 1h = 700
        let kcal = estimateCalories(for: .running, avgSpeedMps: 10 / 3.6, duration: 3600, weightKg: 70)
        XCTAssertEqual(kcal, 700, accuracy: 0.001)
    }

    func test_caloriesScalesWithDuration() {
        let half = estimateCalories(for: .cycling, avgSpeedMps: 20 / 3.6, duration: 1800, weightKg: 70)
        XCTAssertEqual(half, 280, accuracy: 0.001)
    }
}
