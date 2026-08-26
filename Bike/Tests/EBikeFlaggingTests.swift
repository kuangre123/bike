import XCTest
import CyclingDomain
@testable import Bike

/// 「疑似电动车」app 层：派生判定接线 + 徽标开关/排除状态的组合逻辑。
/// （排除/恢复的健康删除与写回依赖 HealthKit 真机环境，不在单测覆盖。）
final class EBikeFlaggingTests: XCTestCase {
    private let flagKey = "ebikeAutoFlag"

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: flagKey)
        super.tearDown()
    }

    /// 匀速高速轨迹造一条骑行模型。
    private func makeSteadyCyclingRide(speedMps: Double = 6.1, minutes: Int = 10) -> RideModel {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let samples = (0..<(minutes * 12)).map { i in
            GPSSample(
                timestamp: start.addingTimeInterval(Double(i) * 5),
                latitude: 31.0 + Double(i) * 1e-5,
                longitude: 121.0,
                speedMps: speedMps
            )
        }
        return RideModel(
            rideID: UUID(),
            activityTypeRaw: ActivityType.cycling.rawValue,
            startDate: start,
            endDate: start.addingTimeInterval(Double(minutes) * 60),
            sourceRaw: RideSource.gpsTracked.rawValue,
            distanceMeters: 4000,
            avgSpeedMps: speedMps,
            calories: 100,
            confidence: 2,
            routeData: RideMapping.encodeRoute(samples)
        )
    }

    func test_steadyRide_isSuspected_andShowsBadge() {
        let ride = makeSteadyCyclingRide()
        XCTAssertTrue(EBikeFlagging.isSuspected(ride))
        XCTAssertTrue(EBikeFlagging.showsBadge(for: ride))
    }

    func test_excludedRide_hidesBadge_flagPersistsOnModel() {
        let ride = makeSteadyCyclingRide()
        ride.excludedAsEBike = true
        XCTAssertTrue(EBikeFlagging.isSuspected(ride), "派生判定与排除状态无关")
        XCTAssertFalse(EBikeFlagging.showsBadge(for: ride), "已排除不再显示徽标")
    }

    func test_autoFlagToggleOff_hidesBadge() {
        UserDefaults.standard.set(false, forKey: flagKey)
        let ride = makeSteadyCyclingRide()
        XCTAssertFalse(EBikeFlagging.autoFlagEnabled)
        XCTAssertFalse(EBikeFlagging.showsBadge(for: ride), "开关关闭后不显示徽标")
    }

    func test_motionOnlyRide_isNotSuspected() {
        let ride = makeSteadyCyclingRide()
        ride.routeData = nil  // motionOnly：无轨迹不判
        XCTAssertFalse(EBikeFlagging.isSuspected(ride))
    }

    func test_newRideDefaultsToNotExcluded() {
        XCTAssertFalse(makeSteadyCyclingRide().excludedAsEBike)
    }
}
