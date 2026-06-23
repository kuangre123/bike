import XCTest
@testable import CyclingDomain

final class BRouterParsingTests: XCTestCase {
    private let sample = """
    {"type":"FeatureCollection","features":[{"type":"Feature",
    "properties":{"track-length":"1500","total-time":"360"},
    "geometry":{"type":"LineString","coordinates":[
    [116.0,39.0,40],[116.001,39.001,41],[116.002,39.002,42]]}}]}
    """

    func test_parsesCoordinatesDistanceTime() {
        let plan = parseBRouterGeoJSON(Data(sample.utf8))
        XCTAssertNotNil(plan)
        XCTAssertEqual(plan?.coordinates.count, 3)
        XCTAssertEqual(plan?.coordinates.first?.latitude, 39.0)
        XCTAssertEqual(plan?.coordinates.first?.longitude, 116.0)
        XCTAssertEqual(plan?.distanceMeters, 1500)
        XCTAssertEqual(plan?.estimatedSeconds, 360)
    }

    func test_invalidJSONReturnsNil() {
        XCTAssertNil(parseBRouterGeoJSON(Data("not json".utf8)))
    }

    func test_missingDistanceFallsBackToPolylineLength() {
        let noLen = """
        {"features":[{"properties":{},"geometry":{"type":"LineString",
        "coordinates":[[0,0,0],[0,0.001,0]]}}]}
        """
        let plan = parseBRouterGeoJSON(Data(noLen.utf8))
        XCTAssertEqual(plan?.distanceMeters ?? 0, 111.2, accuracy: 1.0)
    }
}
