import XCTest
@testable import CyclingDomain

final class RouteSuggestionsTests: XCTestCase {
    private let beijing = GeoCoordinate(latitude: 39.90, longitude: 116.40)

    func test_destination_distanceMatchesRequest() {
        let p = destination(from: beijing, bearingDegrees: 90, distanceMeters: 1_000)
        let d = haversineMeters(lat1: beijing.latitude, lon1: beijing.longitude,
                                lat2: p.latitude, lon2: p.longitude)
        XCTAssertEqual(d, 1_000, accuracy: 1.0)  // 误差 < 1 米
    }

    func test_destination_bearingPreserved() {
        let p = destination(from: beijing, bearingDegrees: 90, distanceMeters: 2_000)
        // 正东走，纬度几乎不变、经度增大
        XCTAssertEqual(p.latitude, beijing.latitude, accuracy: 1e-4)
        XCTAssertGreaterThan(p.longitude, beijing.longitude)
        XCTAssertEqual(bearingDegrees(from: beijing, to: p), 90, accuracy: 0.5)
    }

    func test_loop_startsAndEndsAtOrigin() {
        let wp = loopWaypoints(origin: beijing, targetMeters: 9_000, startBearingDegrees: 30)
        XCTAssertEqual(wp.count, 4)
        XCTAssertEqual(wp.first, beijing)
        XCTAssertEqual(wp.last, beijing)
    }

    func test_loop_straightLinePerimeterApproxTarget() {
        let target = 9_000.0
        let wp = loopWaypoints(origin: beijing, targetMeters: target, startBearingDegrees: 30)
        let perim = polylineLengthMeters(wp)
        // 等边三角形直线周长应非常接近目标（球面近似下 < 0.5% 误差）
        XCTAssertEqual(perim, target, accuracy: target * 0.01)
    }

    func test_loop_isEquilateral() {
        let wp = loopWaypoints(origin: beijing, targetMeters: 12_000, startBearingDegrees: 100)
        let e1 = haversineMeters(lat1: wp[0].latitude, lon1: wp[0].longitude, lat2: wp[1].latitude, lon2: wp[1].longitude)
        let e2 = haversineMeters(lat1: wp[1].latitude, lon1: wp[1].longitude, lat2: wp[2].latitude, lon2: wp[2].longitude)
        let e3 = haversineMeters(lat1: wp[2].latitude, lon1: wp[2].longitude, lat2: wp[3].latitude, lon2: wp[3].longitude)
        XCTAssertEqual(e1, e2, accuracy: e1 * 0.02)
        XCTAssertEqual(e2, e3, accuracy: e2 * 0.02)
    }

    func test_defaultSuggestions_threeAscendingDistances() {
        let s = defaultLoopSuggestions()
        XCTAssertEqual(s.count, 3)
        XCTAssertEqual(s.map(\.targetMeters), [5_000, 10_000, 20_000])
        XCTAssertEqual(Set(s.map(\.id)).count, 3)
    }
}
