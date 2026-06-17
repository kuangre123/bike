import XCTest
@testable import CyclingDomain

final class SpeedFilterTests: XCTestCase {
    func test_typicalCyclingSpeedIsPlausible() {
        XCTAssertTrue(isPlausibleCyclingSpeed(mps: 20 / 3.6)) // 20 km/h
    }
    func test_carSpeedIsNotPlausible() {
        XCTAssertFalse(isPlausibleCyclingSpeed(mps: 80 / 3.6)) // 80 km/h
    }
    func test_walkingSpeedIsNotPlausible() {
        XCTAssertFalse(isPlausibleCyclingSpeed(mps: 4 / 3.6)) // 4 km/h
    }
    func test_boundariesInclusive() {
        XCTAssertTrue(isPlausibleCyclingSpeed(mps: 8 / 3.6))
        XCTAssertTrue(isPlausibleCyclingSpeed(mps: 35 / 3.6))
    }
}
