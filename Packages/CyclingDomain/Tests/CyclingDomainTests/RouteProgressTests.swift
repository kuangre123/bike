import XCTest
@testable import CyclingDomain

final class RouteProgressTests: XCTestCase {
    private let line = [GeoCoordinate(latitude: 0, longitude: 0),
                        GeoCoordinate(latitude: 0, longitude: 0.01)]

    func test_nearestOnSegmentDistance() {
        let p = GeoCoordinate(latitude: 0.001, longitude: 0.005)
        let r = nearestPointOnRoute(p, line)
        XCTAssertEqual(r.distanceMeters, 111.2, accuracy: 5)
        XCTAssertEqual(r.segmentIndex, 0)
    }

    func test_onRouteNotOffRoute() {
        let p = GeoCoordinate(latitude: 0.0001, longitude: 0.005)
        let r = nearestPointOnRoute(p, line)
        XCTAssertFalse(isOffRoute(distanceToRouteMeters: r.distanceMeters))
    }

    func test_offRouteWhenFar() {
        XCTAssertTrue(isOffRoute(distanceToRouteMeters: 80))
    }

    func test_navigationProgressNextTurn() {
        // 直线向东后右转向北
        let coords = [GeoCoordinate(latitude: 0, longitude: 0),
                      GeoCoordinate(latitude: 0, longitude: 0.002),
                      GeoCoordinate(latitude: 0.002, longitude: 0.002)]
        let turns = turnsFromPolyline(coords)
        // 用户在第一段中间
        let loc = GeoCoordinate(latitude: 0, longitude: 0.001)
        let p = navigationProgress(location: loc, coords: coords, turns: turns)
        XCTAssertEqual(p.segmentIndex, 0)
        XCTAssertNotNil(p.nextTurn)
        XCTAssertEqual(p.nextTurn?.coordinateIndex, 1)
        XCTAssertGreaterThan(p.distanceToNextTurnMeters, 0)
    }
}
