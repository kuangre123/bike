import XCTest
@testable import CyclingDomain

final class TurnDetectionTests: XCTestCase {
    func test_straightLineNoTurns() {
        let coords = [GeoCoordinate(latitude: 0, longitude: 0),
                      GeoCoordinate(latitude: 0.001, longitude: 0),
                      GeoCoordinate(latitude: 0.002, longitude: 0)]
        let turns = turnsFromPolyline(coords)
        XCTAssertEqual(turns.filter { $0.direction != .arrive }.count, 0)
        XCTAssertEqual(turns.last?.direction, .arrive)
    }

    func test_rightTurnDetected() {
        let coords = [GeoCoordinate(latitude: 0, longitude: 0),
                      GeoCoordinate(latitude: 0.001, longitude: 0),
                      GeoCoordinate(latitude: 0.001, longitude: 0.001)]
        let real = turnsFromPolyline(coords).filter { $0.direction != .arrive }
        XCTAssertEqual(real.count, 1)
        XCTAssertEqual(real.first?.direction, .right)
        XCTAssertEqual(real.first?.coordinateIndex, 1)
    }

    func test_leftTurnDetected() {
        let coords = [GeoCoordinate(latitude: 0, longitude: 0),
                      GeoCoordinate(latitude: 0.001, longitude: 0),
                      GeoCoordinate(latitude: 0.001, longitude: -0.001)]
        let turns = turnsFromPolyline(coords).filter { $0.direction != .arrive }
        XCTAssertEqual(turns.first?.direction, .left)
    }
}
