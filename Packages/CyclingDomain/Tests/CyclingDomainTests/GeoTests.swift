import XCTest
@testable import CyclingDomain

final class GeoTests: XCTestCase {
    func test_bearingNorth() {
        let b = bearingDegrees(from: GeoCoordinate(latitude: 0, longitude: 0),
                               to: GeoCoordinate(latitude: 1, longitude: 0))
        XCTAssertEqual(b, 0, accuracy: 0.5)
    }
    func test_bearingEast() {
        let b = bearingDegrees(from: GeoCoordinate(latitude: 0, longitude: 0),
                               to: GeoCoordinate(latitude: 0, longitude: 1))
        XCTAssertEqual(b, 90, accuracy: 0.5)
    }
    func test_signedTurnRight() {
        XCTAssertEqual(signedTurnDegrees(incoming: 0, outgoing: 90), 90, accuracy: 0.001)
    }
    func test_signedTurnLeftWraps() {
        XCTAssertEqual(signedTurnDegrees(incoming: 0, outgoing: 270), -90, accuracy: 0.001)
    }
}
