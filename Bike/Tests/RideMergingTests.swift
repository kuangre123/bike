import XCTest
import CyclingDomain
@testable import Bike

final class RideMergingTests: XCTestCase {
    private func makeRide(
        type: ActivityType = .cycling,
        start: TimeInterval, end: TimeInterval,
        distance: Double? = nil, calories: Double? = nil,
        hr: Double? = nil, confidence: Int = 2,
        source: RideSource = .gpsTracked,
        route: [GPSSample]? = nil
    ) -> RideModel {
        RideModel(
            rideID: UUID(),
            activityTypeRaw: type.rawValue,
            startDate: Date(timeIntervalSince1970: start),
            endDate: Date(timeIntervalSince1970: end),
            sourceRaw: source.rawValue,
            distanceMeters: distance,
            avgSpeedMps: nil,
            calories: calories,
            confidence: confidence,
            routeData: RideMapping.encodeRoute(route),
            avgHeartRate: hr
        )
    }

    // MARK: - canMerge 门槛

    func test_canMerge_sameTypeWithinGap() {
        let a = makeRide(start: 0, end: 600)
        let b = makeRide(start: 900, end: 1500)   // 间隔 5 分钟
        XCTAssertTrue(RideMerging.canMerge(a, b))
        XCTAssertTrue(RideMerging.canMerge(b, a), "顺序无关")
    }

    func test_canMerge_rejectsDifferentType() {
        let a = makeRide(type: .cycling, start: 0, end: 600)
        let b = makeRide(type: .walking, start: 900, end: 1500)
        XCTAssertFalse(RideMerging.canMerge(a, b))
    }

    func test_canMerge_rejectsGapOverTwoHours() {
        let a = makeRide(start: 0, end: 600)
        let b = makeRide(start: 600 + 2 * 3600 + 1, end: 600 + 2 * 3600 + 601)
        XCTAssertFalse(RideMerging.canMerge(a, b))
    }

    func test_canMerge_rejectsExcluded() {
        let a = makeRide(start: 0, end: 600)
        let b = makeRide(start: 900, end: 1500)
        b.excludedAsEBike = true
        XCTAssertFalse(RideMerging.canMerge(a, b))
    }

    // MARK: - apply 字段合并

    func test_apply_sumsDurationsExcludingGap() {
        let a = makeRide(start: 0, end: 600)          // 10 分钟
        let b = makeRide(start: 1200, end: 1500)      // 5 分钟，间隔 10 分钟
        RideMerging.apply(absorbing: b, into: a)
        XCTAssertEqual(a.startDate, Date(timeIntervalSince1970: 0))
        XCTAssertEqual(a.endDate, Date(timeIntervalSince1970: 1500))
        XCTAssertEqual(a.duration, 900, accuracy: 0.001, "时长 = 两段之和，间隙不计入")
    }

    func test_apply_sumsDistanceAndCalories_recomputesSpeed() {
        let a = makeRide(start: 0, end: 600, distance: 3000, calories: 100)
        let b = makeRide(start: 900, end: 1500, distance: 1500, calories: 50)
        RideMerging.apply(absorbing: b, into: a)
        XCTAssertEqual(a.distanceMeters, 4500)
        XCTAssertEqual(a.calories, 150)
        XCTAssertEqual(a.avgSpeedMps ?? 0, 4500 / 1200, accuracy: 0.001, "均速 = 总距离 / 总有效时长")
    }

    func test_apply_nilMetricsStayNil() {
        let a = makeRide(start: 0, end: 600)
        let b = makeRide(start: 900, end: 1500)
        RideMerging.apply(absorbing: b, into: a)
        XCTAssertNil(a.distanceMeters)
        XCTAssertNil(a.avgSpeedMps)
        XCTAssertNil(a.calories)
        XCTAssertNil(a.avgHeartRate)
    }

    func test_apply_weightsHeartRateByDuration() {
        let a = makeRide(start: 0, end: 600, hr: 120)     // 600s @120
        let b = makeRide(start: 900, end: 1200, hr: 150)  // 300s @150
        RideMerging.apply(absorbing: b, into: a)
        XCTAssertEqual(a.avgHeartRate ?? 0, (120.0 * 600 + 150.0 * 300) / 900, accuracy: 0.001)
    }

    func test_apply_concatenatesRouteSortedByTime() {
        let routeA = [GPSSample(timestamp: Date(timeIntervalSince1970: 10), latitude: 1, longitude: 1, speedMps: 5)]
        let routeB = [GPSSample(timestamp: Date(timeIntervalSince1970: 5), latitude: 2, longitude: 2, speedMps: 6)]
        let a = makeRide(start: 0, end: 600, route: routeA)
        let b = makeRide(start: 900, end: 1500, route: routeB)
        RideMerging.apply(absorbing: b, into: a)
        let merged = RideMapping.decodeRoute(a.routeData)
        XCTAssertEqual(merged.count, 2)
        XCTAssertEqual(merged[0].timestamp, Date(timeIntervalSince1970: 5), "按时间排序")
    }

    func test_apply_differentSourcesBecomeMerged_autoDetectedCleared() {
        let a = makeRide(start: 0, end: 600, source: .gpsTracked)
        let b = makeRide(start: 900, end: 1500, source: .motionOnly)
        a.isAutoDetected = true
        RideMerging.apply(absorbing: b, into: a)
        XCTAssertEqual(a.sourceRaw, RideSource.merged.rawValue)
        XCTAssertFalse(a.isAutoDetected)
    }

    // MARK: - 合并涉及第三方导入记录

    /// 合并后这条不再是「原样搬来的那条 Garmin 记录」，导入标记要清掉
    /// （防重复导入改由墓碑负责），但来源名保留，用户仍看得出数据来自哪儿。
    func test_apply_clearsImportMarkerButKeepsSourceName() {
        let survivor = makeRide(start: 0, end: 600, source: .gpsTracked)
        survivor.externalWorkoutUUID = UUID()
        survivor.externalSourceName = "Garmin Connect"
        let absorbed = makeRide(start: 900, end: 1500, source: .gpsTracked)

        RideMerging.apply(absorbing: absorbed, into: survivor)

        XCTAssertNil(survivor.externalWorkoutUUID, "合并后不得再冒充某条原始导入记录")
        XCTAssertEqual(survivor.externalSourceName, "Garmin Connect")
    }

    /// 只有被吸收的那条是导入记录时，来源名要传给幸存者。
    func test_apply_inheritsSourceNameFromAbsorbed() {
        let survivor = makeRide(start: 0, end: 600, source: .gpsTracked)
        let absorbed = makeRide(start: 900, end: 1500, source: .gpsTracked)
        absorbed.externalWorkoutUUID = UUID()
        absorbed.externalSourceName = "华为运动健康"

        RideMerging.apply(absorbing: absorbed, into: survivor)

        XCTAssertEqual(survivor.externalSourceName, "华为运动健康")
    }
}
