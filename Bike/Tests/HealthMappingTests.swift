import XCTest
import HealthKit
import CyclingDomain
@testable import Bike

final class HealthMappingTests: XCTestCase {
    func test_workoutActivityTypeMapping() {
        XCTAssertEqual(HealthService.workoutActivityType(for: .walking), .walking)
        XCTAssertEqual(HealthService.workoutActivityType(for: .running), .running)
        XCTAssertEqual(HealthService.workoutActivityType(for: .cycling), .cycling)
        XCTAssertEqual(HealthService.workoutActivityType(for: .other), .other)
    }

    func test_routeCodecRoundTrip() {
        let samples = [
            GPSSample(timestamp: Date(timeIntervalSince1970: 0), latitude: 1.0, longitude: 2.0, speedMps: 5),
            GPSSample(timestamp: Date(timeIntervalSince1970: 60), latitude: 1.001, longitude: 2.001, speedMps: 6),
        ]
        let data = RideMapping.encodeRoute(samples)
        XCTAssertNotNil(data)
        let decoded = RideMapping.decodeRoute(data)
        XCTAssertEqual(decoded.count, 2)
        XCTAssertEqual(decoded[0].latitude, 1.0, accuracy: 1e-9)
        XCTAssertEqual(decoded[1].speedMps, 6, accuracy: 1e-9)
    }

    func test_encodeEmptyOrNilRouteIsNil() {
        XCTAssertNil(RideMapping.encodeRoute(nil))
        XCTAssertNil(RideMapping.encodeRoute([]))
        XCTAssertTrue(RideMapping.decodeRoute(nil).isEmpty)
    }
}
