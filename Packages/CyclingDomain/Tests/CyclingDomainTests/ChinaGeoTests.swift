import XCTest
@testable import CyclingDomain

final class ChinaGeoTests: XCTestCase {
    func test_beijingShiftIsHundredsOfMeters() {
        let wgs = GeoCoordinate(latitude: 39.90105, longitude: 116.42079) // 天安门附近 WGS
        let gcj = ChinaGeo.wgs84ToGcj02(wgs)
        let dLat = gcj.latitude - wgs.latitude
        let dLon = gcj.longitude - wgs.longitude
        // 北京偏移：纬度 ~+0.001~0.003，经度 ~+0.005~0.007（合计几百米）
        XCTAssertTrue(dLat > 0.0005 && dLat < 0.004, "dLat=\(dLat)")
        XCTAssertTrue(dLon > 0.003 && dLon < 0.009, "dLon=\(dLon)")
    }

    func test_roundTripWithinAMeter() {
        let gcj = GeoCoordinate(latitude: 39.915, longitude: 116.404)
        let wgs = ChinaGeo.gcj02ToWgs84(gcj)
        let back = ChinaGeo.wgs84ToGcj02(wgs)
        XCTAssertEqual(back.latitude, gcj.latitude, accuracy: 1e-5)
        XCTAssertEqual(back.longitude, gcj.longitude, accuracy: 1e-5)
    }

    func test_outsideChinaUnchanged() {
        let nyc = GeoCoordinate(latitude: 40.7128, longitude: -74.006)
        let g = ChinaGeo.wgs84ToGcj02(nyc)
        XCTAssertEqual(g.latitude, nyc.latitude)
        XCTAssertEqual(g.longitude, nyc.longitude)
    }
}
