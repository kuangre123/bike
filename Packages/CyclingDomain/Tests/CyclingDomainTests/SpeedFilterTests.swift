import XCTest
@testable import CyclingDomain

final class SpeedFilterTests: XCTestCase {
    func test_cyclingRange() {
        XCTAssertTrue(isPlausibleSpeed(mps: 20 / 3.6, for: .cycling))
        XCTAssertFalse(isPlausibleSpeed(mps: 80 / 3.6, for: .cycling)) // 太快=驾车
        XCTAssertFalse(isPlausibleSpeed(mps: 4 / 3.6, for: .cycling))  // 太慢
    }

    func test_walkingRange() {
        XCTAssertTrue(isPlausibleSpeed(mps: 4 / 3.6, for: .walking))
        XCTAssertFalse(isPlausibleSpeed(mps: 20 / 3.6, for: .walking)) // 步行不可能 20km/h
    }

    func test_runningRange() {
        XCTAssertTrue(isPlausibleSpeed(mps: 12 / 3.6, for: .running))
        XCTAssertFalse(isPlausibleSpeed(mps: 3 / 3.6, for: .running))  // 太慢不算跑
    }

    func test_typeSpecificity() {
        // 4 km/h 对步行合理、对跑步不合理
        XCTAssertTrue(isPlausibleSpeed(mps: 4 / 3.6, for: .walking))
        XCTAssertFalse(isPlausibleSpeed(mps: 4 / 3.6, for: .running))
    }
}
