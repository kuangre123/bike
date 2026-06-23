import XCTest
@testable import CyclingDomain

final class RoutePlanTests: XCTestCase {
    func test_polylineLengthTwoPoints() {
        let coords = [GeoCoordinate(latitude: 0, longitude: 0),
                      GeoCoordinate(latitude: 0.001, longitude: 0)]
        XCTAssertEqual(polylineLengthMeters(coords), 111.2, accuracy: 1.0)
    }

    func test_polylineLengthFewerThanTwoIsZero() {
        XCTAssertEqual(polylineLengthMeters([]), 0)
        XCTAssertEqual(polylineLengthMeters([GeoCoordinate(latitude: 1, longitude: 1)]), 0)
    }

    func test_routePlanDurationMinutes() {
        let plan = RoutePlan(coordinates: [], distanceMeters: 0, estimatedSeconds: 1800)
        XCTAssertEqual(plan.estimatedMinutes, 30)
    }
}
