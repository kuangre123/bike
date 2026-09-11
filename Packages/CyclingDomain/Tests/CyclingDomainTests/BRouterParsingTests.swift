import XCTest
@testable import CyclingDomain

/// 用**真实 BRouter 响应**做的解析测试。
///
/// 下面这段 JSON 是从 brouter.de 实际返回里原样截取的（北京一段路的前 5 个点、前 3 段），
/// 结构没有改动——手写的假数据只能证明代码符合我的想象，证明不了它能解析真实响应。
final class BRouterParsingTests: XCTestCase {

    private let realResponse = "{\"type\":\"FeatureCollection\",\"features\":[{\"type\":\"Feature\",\"properties\":{\"creator\":\"BRouter-1.7.10\",\"track-length\":\"234\",\"total-time\":\"67\",\"messages\":[[\"Longitude\",\"Latitude\",\"Elevation\",\"Distance\",\"CostPerKm\",\"ElevCost\",\"TurnCost\",\"NodeCost\",\"InitialCost\",\"WayTags\",\"NodeTags\",\"Time\",\"Energy\"],[\"116397056\",\"39907228\",\"49\",\"197\",\"1450\",\"0\",\"0\",\"0\",\"0\",\"reversedirection=yes highway=tertiary surface=asphalt smoothness=excellent\",\"highway=crossing\",\"30\",\"3096\"],[\"116397071\",\"39906928\",\"49\",\"33\",\"1450\",\"0\",\"0\",\"0\",\"0\",\"reversedirection=yes highway=tertiary surface=asphalt smoothness=excellent\",\"\",\"36\",\"3651\"],[\"116397074\",\"39906895\",\"49\",\"4\",\"1450\",\"0\",\"0\",\"0\",\"0\",\"reversedirection=yes highway=tertiary\",\"barrier=gate\",\"37\",\"3718\"]]},\"geometry\":{\"type\":\"LineString\",\"coordinates\":[[116.396968,39.908999,50.25],[116.397015,39.90807,50.0],[116.397023,39.907899,49.75],[116.397039,39.907574,49.5],[116.397048,39.907395,49.5]]}}]}"

    private var data: Data { realResponse.data(using: .utf8)! }

    func testParsesCoordinates() {
        let plan = parseBRouterGeoJSON(data)
        XCTAssertEqual(plan?.coordinates.count, 5)
        // GeoJSON 是 [经度, 纬度]，别搞反
        XCTAssertEqual(plan?.coordinates.first?.latitude ?? 0, 39.908999, accuracy: 0.000001)
        XCTAssertEqual(plan?.coordinates.first?.longitude ?? 0, 116.396968, accuracy: 0.000001)
    }

    /// 这一条是这次改动的重点：第三维海拔以前被丢掉了。
    func testKeepsElevationThirdDimension() {
        let plan = parseBRouterGeoJSON(data)
        XCTAssertEqual(plan?.elevations, [50.25, 50.0, 49.75, 49.5, 49.5])
    }

    func testParsesSegmentsWithCumulativeDistance() {
        let plan = parseBRouterGeoJSON(data)
        XCTAssertEqual(plan?.segments.count, 3)
        XCTAssertEqual(plan?.segments.map(\.lengthMeters), [197, 33, 4])
        // 累计距离：0, 197, 230
        XCTAssertEqual(plan?.segments.map(\.startDistanceMeters), [0, 197, 230])
    }

    func testParsesWayTagsFromRealResponse() {
        let plan = parseBRouterGeoJSON(data)
        XCTAssertEqual(plan?.segments.first?.surface, "asphalt")
        XCTAssertEqual(plan?.segments.first?.highway, "tertiary")
        XCTAssertEqual(plan?.segments.first?.isPaved, true)
        // 第三段只有 highway，没有 surface —— 判不出铺装与否
        XCTAssertNil(plan?.segments.last?.isPaved)
    }

    func testUsesTrackLengthNotPolylineLength() {
        XCTAssertEqual(parseBRouterGeoJSON(data)?.distanceMeters, 234)
    }

    func testAscentIsComputedFromElevations() {
        // 这段一路下降，累计爬升是 0（不是 nil——有数据，只是没有上坡）
        XCTAssertEqual(parseBRouterGeoJSON(data)?.ascentMeters, 0)
    }

    /// BRouter 的 `filtered ascend` 做过噪声滤波，比我们把每点高差裸加靠谱。
    /// 实测同一条山路：裸加 1307 m，BRouter 1173 m——裸加会系统性偏高。
    func testPrefersBRouterFilteredAscentOverRawSummation() {
        let json = """
        {"type":"FeatureCollection","features":[{\
        "geometry":{"coordinates":[[116.4,39.9,100.0],[116.5,39.9,150.0],[116.6,39.9,120.0]]},\
        "properties":{"track-length":"100","filtered ascend":"42"}}]}
        """
        let plan = parseBRouterGeoJSON(Data(json.utf8))
        // 裸加会得到 50（100→150）；应该采信 BRouter 的 42
        XCTAssertEqual(plan?.reportedAscentMeters, 42)
        XCTAssertEqual(plan?.ascentMeters, 42)
    }

    func testFallsBackToComputedAscentWhenBRouterOmitsIt() {
        let json = """
        {"type":"FeatureCollection","features":[{\
        "geometry":{"coordinates":[[116.4,39.9,100.0],[116.5,39.9,150.0],[116.6,39.9,120.0]]},\
        "properties":{"track-length":"100"}}]}
        """
        let plan = parseBRouterGeoJSON(Data(json.utf8))
        XCTAssertNil(plan?.reportedAscentMeters)
        XCTAssertEqual(plan?.ascentMeters, 50)
    }

    /// 回归：1.4 里 RouteService 做 GCJ-02 对齐时手工重建 RoutePlan，只传了三个字段，
    /// 海拔 / 逐段 / 爬升全丢——路况预警因此从没工作过。withCoordinates 必须一个都不丢。
    func testWithCoordinatesPreservesEverythingButCoordinates() {
        let plan = try! XCTUnwrap(parseBRouterGeoJSON(data))
        let shifted = plan.coordinates.map {
            GeoCoordinate(latitude: $0.latitude + 0.002, longitude: $0.longitude + 0.005)
        }
        let aligned = plan.withCoordinates(shifted)

        XCTAssertEqual(aligned.coordinates, shifted)
        XCTAssertEqual(aligned.elevations, plan.elevations)
        XCTAssertEqual(aligned.segments, plan.segments)
        XCTAssertEqual(aligned.reportedAscentMeters, plan.reportedAscentMeters)
        XCTAssertEqual(aligned.turns, plan.turns)
        XCTAssertEqual(aligned.distanceMeters, plan.distanceMeters)
        XCTAssertEqual(aligned.estimatedSeconds, plan.estimatedSeconds)
        // 最关键的：预警不能因为对齐就消失
        XCTAssertEqual(aligned.warnings, plan.warnings)
        XCTAssertEqual(aligned.ascentMeters, plan.ascentMeters)
    }

    func testGarbageDataReturnsNil() {
        XCTAssertNil(parseBRouterGeoJSON(Data("not json".utf8)))
        XCTAssertNil(parseBRouterGeoJSON(Data("{}".utf8)))
    }

    /// 没有 messages 时不该崩，只是没有逐段信息。
    func testMissingMessagesYieldsEmptySegments() {
        let stripped = "{\"type\":\"FeatureCollection\",\"features\":[{\"geometry\":{\"coordinates\":[[116.4,39.9,50.0],[116.5,39.9,52.0]]},\"properties\":{\"track-length\":\"100\"}}]}"
        let plan = parseBRouterGeoJSON(Data(stripped.utf8))
        XCTAssertEqual(plan?.coordinates.count, 2)
        XCTAssertTrue(plan?.segments.isEmpty ?? false)
        XCTAssertEqual(plan?.ascentMeters, 2)
    }
}
