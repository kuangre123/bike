import XCTest
import CyclingDomain
@testable import Bike

final class RideMappingTests: XCTestCase {
    func test_makeModel_mapsScalarFields() {
        let ride = Ride(
            start: Date(timeIntervalSince1970: 0),
            end: Date(timeIntervalSince1970: 600),
            source: .merged, distanceMeters: 3000,
            avgSpeedMps: 5, calories: 120, confidence: 2
        )
        let model = RideMapping.makeModel(from: ride)
        XCTAssertEqual(model.startDate, ride.start)
        XCTAssertEqual(model.endDate, ride.end)
        XCTAssertEqual(model.sourceRaw, "merged")
        XCTAssertEqual(model.distanceMeters, 3000)
        XCTAssertEqual(model.calories, 120)
        XCTAssertEqual(model.confidence, 2)
        XCTAssertEqual(RideMapping.source(of: model), .merged)
    }

    func test_motionOnly_hasNilMetrics() {
        let ride = Ride(
            start: Date(timeIntervalSince1970: 0),
            end: Date(timeIntervalSince1970: 300),
            source: .motionOnly, distanceMeters: nil,
            avgSpeedMps: nil, calories: nil, confidence: 1
        )
        let model = RideMapping.makeModel(from: ride)
        XCTAssertNil(model.distanceMeters)
        XCTAssertNil(model.calories)
        XCTAssertEqual(RideMapping.source(of: model), .motionOnly)
    }
}
