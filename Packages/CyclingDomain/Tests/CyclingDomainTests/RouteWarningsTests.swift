import XCTest
@testable import CyclingDomain

final class RouteTerrainTests: XCTestCase {

    func testParsesTagsFromBRouterFormat() {
        let tags = RouteTerrain.parseTags("highway=tertiary surface=asphalt smoothness=excellent")
        XCTAssertEqual(tags["highway"], "tertiary")
        XCTAssertEqual(tags["surface"], "asphalt")
        XCTAssertEqual(tags["smoothness"], "excellent")
    }

    /// `cycleway:right=lane` 的键里带冒号、值里没有——只能按第一个 `=` 切。
    func testParsesTagKeysContainingColon() {
        let tags = RouteTerrain.parseTags("highway=primary cycleway:right=lane")
        XCTAssertEqual(tags["cycleway:right"], "lane")
    }

    func testEmptyTagStringYieldsNoTags() {
        XCTAssertTrue(RouteTerrain.parseTags("").isEmpty)
    }

    func testPavedAndUnpavedClassification() {
        XCTAssertEqual(segment(tags: ["surface": "asphalt"]).isPaved, true)
        XCTAssertEqual(segment(tags: ["surface": "gravel"]).isPaved, false)
    }

    /// OSM 的 surface 覆盖率不完整，缺标签既不代表土路也不代表柏油路。
    func testMissingSurfaceIsUnknownNotAssumedPaved() {
        XCTAssertNil(segment(tags: ["highway": "tertiary"]).isPaved)
    }

    func testUnknownSurfaceValueIsUnknown() {
        XCTAssertNil(segment(tags: ["surface": "something_new"]).isPaved)
    }

    func testCyclewayDetection() {
        XCTAssertTrue(segment(tags: ["highway": "cycleway"]).hasCycleway)
        XCTAssertTrue(segment(tags: ["highway": "primary", "cycleway:right": "lane"]).hasCycleway)
        XCTAssertFalse(segment(tags: ["highway": "primary"]).hasCycleway)
    }

    private func segment(tags: [String: String]) -> RouteSegment {
        RouteSegment(startDistanceMeters: 0, lengthMeters: 100, tags: tags)
    }
}

final class RouteWarningsTests: XCTestCase {

    // MARK: - 路面

    func testContiguousUnpavedSegmentsMergeIntoOneWarning() {
        let segments = [
            seg(0, 100, ["surface": "asphalt"]),
            seg(100, 200, ["surface": "gravel"]),
            seg(300, 150, ["surface": "dirt"]),
            seg(450, 100, ["surface": "asphalt"]),
        ]
        let warnings = RouteAnalysis.surfaceWarnings(segments)
        XCTAssertEqual(warnings.count, 1)
        XCTAssertEqual(warnings[0].startDistanceMeters, 100)
        XCTAssertEqual(warnings[0].lengthMeters, 350)
    }

    /// 一小段碎石不值得报，否则一条路能刷出几十条提醒。
    func testShortUnpavedRunIsIgnored() {
        let segments = [seg(0, 100, ["surface": "asphalt"]), seg(100, 20, ["surface": "gravel"])]
        XCTAssertTrue(RouteAnalysis.surfaceWarnings(segments).isEmpty)
    }

    func testSegmentsWithoutSurfaceTagProduceNoWarning() {
        let segments = [seg(0, 500, ["highway": "residential"])]
        XCTAssertTrue(RouteAnalysis.surfaceWarnings(segments).isEmpty)
    }

    // MARK: - 危险路段

    func testBusyRoadWithoutCyclewayIsWarned() {
        let warnings = RouteAnalysis.busyRoadWarnings([seg(0, 300, ["highway": "primary"])])
        XCTAssertEqual(warnings.count, 1)
        XCTAssertEqual(warnings[0].kind, .busyRoad(highway: "primary"))
    }

    /// 有自行车道就不算危险——干道 + 自行车道往往比小路还好骑。
    func testBusyRoadWithCyclewayIsNotWarned() {
        let segments = [seg(0, 300, ["highway": "primary", "cycleway:right": "track"])]
        XCTAssertTrue(RouteAnalysis.busyRoadWarnings(segments).isEmpty)
    }

    func testQuietRoadIsNotWarned() {
        XCTAssertTrue(RouteAnalysis.busyRoadWarnings([seg(0, 500, ["highway": "residential"])]).isEmpty)
    }

    // MARK: - 坡度

    func testSustainedClimbIsWarned() {
        // 向北 400 米爬升 40 米 = 10%
        let (coords, elevs) = northLine(lengthMeters: 400, totalRise: 40)
        let warnings = RouteAnalysis.climbWarnings(coordinates: coords, elevations: elevs)
        XCTAssertEqual(warnings.count, 1)
        guard case .steepClimb(let percent) = warnings[0].kind else {
            return XCTFail("应该是爬坡，实际 \(warnings[0].kind)")
        }
        XCTAssertEqual(percent, 10, accuracy: 1.5)
    }

    func testSustainedDescentIsWarnedSeparately() {
        let (coords, elevs) = northLine(lengthMeters: 400, totalRise: -40)
        let warnings = RouteAnalysis.climbWarnings(coordinates: coords, elevations: elevs)
        XCTAssertEqual(warnings.count, 1)
        guard case .steepDescent(let percent) = warnings[0].kind else {
            return XCTFail("应该是下坡，实际 \(warnings[0].kind)")
        }
        XCTAssertEqual(percent, 10, accuracy: 1.5)
    }

    func testGentleSlopeIsNotWarned() {
        let (coords, elevs) = northLine(lengthMeters: 400, totalRise: 8)  // 2%
        XCTAssertTrue(RouteAnalysis.climbWarnings(coordinates: coords, elevations: elevs).isEmpty)
    }

    /// SRTM 约 30 米分辨率：短于基线的距离上算出来的是噪声，不能报。
    func testRouteShorterThanGradientBaseProducesNoWarning() {
        let (coords, elevs) = northLine(lengthMeters: 60, totalRise: 12)  // 20%，但太短
        XCTAssertTrue(RouteAnalysis.climbWarnings(coordinates: coords, elevations: elevs).isEmpty)
    }

    func testMissingElevationsProduceNoWarning() {
        let (coords, _) = northLine(lengthMeters: 400, totalRise: 40)
        XCTAssertTrue(RouteAnalysis.climbWarnings(coordinates: coords, elevations: []).isEmpty)
    }

    /// 海拔数组和坐标对不上时宁可不报，也不要错位配对算出假坡度。
    func testMismatchedElevationCountProducesNoWarning() {
        let (coords, elevs) = northLine(lengthMeters: 400, totalRise: 40)
        XCTAssertTrue(
            RouteAnalysis.climbWarnings(coordinates: coords, elevations: Array(elevs.dropLast())).isEmpty)
    }

    // MARK: - 步道 / 台阶

    func testFootwayIsWarned() {
        let warnings = RouteAnalysis.footOnlyWarnings([seg(0, 120, ["highway": "footway"])])
        XCTAssertEqual(warnings.count, 1)
        XCTAssertEqual(warnings[0].kind, .footOnly(highway: "footway"))
    }

    func testStepsAreWarned() {
        let warnings = RouteAnalysis.footOnlyWarnings([seg(0, 60, ["highway": "steps"])])
        XCTAssertEqual(warnings.first?.kind, .footOnly(highway: "steps"))
    }

    /// `path` 是山地车 / Gravel 的正常路面，警告它会让这两个档没法用。
    func testPathIsNotWarnedAsFootOnly() {
        XCTAssertTrue(RouteAnalysis.footOnlyWarnings([seg(0, 500, ["highway": "path"])]).isEmpty)
    }

    // MARK: - 汇总

    func testWarningsAreSortedByDistanceFromStart() {
        let segments = [
            seg(0, 100, ["surface": "asphalt"]),
            seg(100, 200, ["highway": "trunk"]),
            seg(300, 200, ["surface": "gravel"]),
        ]
        let warnings = RouteAnalysis.warnings(coordinates: [], elevations: [], segments: segments)
        XCTAssertEqual(warnings.map(\.startDistanceMeters), [100, 300])
    }

    // MARK: - helpers

    private func seg(_ start: Double, _ length: Double, _ tags: [String: String]) -> RouteSegment {
        RouteSegment(startDistanceMeters: start, lengthMeters: length, tags: tags)
    }

    /// 一条正北方向、等间距、海拔线性变化的折线。
    private func northLine(lengthMeters: Double, totalRise: Double) -> ([GeoCoordinate], [Double]) {
        let steps = 40
        let metersPerDegreeLat = 111_320.0
        var coords: [GeoCoordinate] = []
        var elevs: [Double] = []
        for i in 0...steps {
            let fraction = Double(i) / Double(steps)
            coords.append(GeoCoordinate(
                latitude: 39.9 + fraction * lengthMeters / metersPerDegreeLat, longitude: 116.4))
            elevs.append(50 + fraction * totalRise)
        }
        return (coords, elevs)
    }
}
