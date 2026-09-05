import XCTest
import SwiftData
import CyclingDomain
@testable import Bike

/// RideStore 去重规则：手动实录 vs 自动检测的胜负关系。
/// 背景 bug：骑行途中被动检测先存了估算记录，用户的码表实录曾被整条静默丢弃。
@MainActor
final class RideStoreTests: XCTestCase {
    private func makeContext() throws -> ModelContext {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: RideModel.self, configurations: config)
        return ModelContext(container)
    }

    private func date(_ t: TimeInterval) -> Date { Date(timeIntervalSince1970: 1_700_000_000 + t) }

    /// 18 分钟带轨迹的手动骑行（gpsTracked）。
    private func manualRide(start: TimeInterval = 0, end: TimeInterval = 1080) -> Ride {
        let samples = [
            GPSSample(timestamp: date(start), latitude: 31.23, longitude: 121.47, speedMps: 2),
            GPSSample(timestamp: date(end), latitude: 31.24, longitude: 121.48, speedMps: 2),
        ]
        return Ride(activityType: .cycling, start: date(start), end: date(end), source: .gpsTracked,
                    distanceMeters: 2100, avgSpeedMps: 1.9, calories: 88, confidence: 2, route: samples)
    }

    /// 预置一条已存在的记录。
    @discardableResult
    private func insertModel(
        _ context: ModelContext, start: TimeInterval, end: TimeInterval,
        auto: Bool, healthUUID: UUID? = nil
    ) -> RideModel {
        let m = RideModel(
            rideID: UUID(), activityTypeRaw: "cycling",
            startDate: date(start), endDate: date(end),
            sourceRaw: auto ? "motionOnly" : "gpsTracked",
            distanceMeters: 2100, avgSpeedMps: 1.8, calories: 88, confidence: 1,
            healthKitWorkoutUUID: healthUUID, isAutoDetected: auto
        )
        context.insert(m)
        try? context.save()
        return m
    }

    func test_manualRide_replacesOverlappingAutoRecord() throws {
        let context = try makeContext()
        let workoutUUID = UUID()
        insertModel(context, start: 0, end: 600, auto: true, healthUUID: workoutUUID)  // 途中存的估算记录

        let result = try RideStore(context: context).save([manualRide()], autoDetected: false)

        XCTAssertEqual(result.inserted.count, 1, "手动实录必须保存成功")
        XCTAssertEqual(result.replacedHealthWorkoutUUIDs, [workoutUUID], "被替换记录的健康 workout 待清理")
        let all = try context.fetch(FetchDescriptor<RideModel>())
        XCTAssertEqual(all.count, 1)
        XCTAssertFalse(all[0].isAutoDetected)
        XCTAssertNotNil(all[0].routeData, "实录轨迹要保住")
    }

    func test_manualRide_coexistsWithMinorBoundaryOverlap() throws {
        let context = try makeContext()
        insertModel(context, start: -600, end: 30, auto: true)  // 只擦到开头 30 秒（< 60 秒容忍）

        let result = try RideStore(context: context).save([manualRide()], autoDetected: false)

        XCTAssertEqual(result.inserted.count, 1)
        XCTAssertTrue(result.replacedHealthWorkoutUUIDs.isEmpty)
        XCTAssertEqual(try context.fetch(FetchDescriptor<RideModel>()).count, 2, "轻微边界重叠应共存")
    }

    func test_manualRide_blockedByOverlappingManualRecord() throws {
        let context = try makeContext()
        insertModel(context, start: 0, end: 900, auto: false)  // 已有手动记录

        let result = try RideStore(context: context).save([manualRide()], autoDetected: false)

        XCTAssertTrue(result.inserted.isEmpty, "不得覆盖已有手动记录")
        XCTAssertEqual(try context.fetch(FetchDescriptor<RideModel>()).count, 1)
    }

    func test_autoRide_neverReplacesManualRecord() throws {
        let context = try makeContext()
        insertModel(context, start: 0, end: 1080, auto: false, healthUUID: UUID())

        let auto = Ride(activityType: .cycling, start: date(0), end: date(900), source: .motionOnly,
                        distanceMeters: nil, avgSpeedMps: nil, calories: nil, confidence: 1)
        let result = try RideStore(context: context).save([auto], autoDetected: true)

        XCTAssertTrue(result.inserted.isEmpty)
        XCTAssertTrue(result.replacedHealthWorkoutUUIDs.isEmpty)
        let all = try context.fetch(FetchDescriptor<RideModel>())
        XCTAssertEqual(all.count, 1)
        XCTAssertFalse(all[0].isAutoDetected, "手动记录保持原样")
    }

    func test_autoRide_upgradeReplacesWorseAuto_reportsHealthUUID() throws {
        let context = try makeContext()
        let oldUUID = UUID()
        // 旧自动记录无轨迹；新自动结果带轨迹 → 视为更完整，替换并上报旧 workout UUID
        let old = insertModel(context, start: 0, end: 900, auto: true, healthUUID: oldUUID)
        old.routeData = nil
        try context.save()

        let upgraded = manualRideAsAuto()
        let result = try RideStore(context: context).save([upgraded], autoDetected: true)

        XCTAssertEqual(result.inserted.count, 1)
        XCTAssertEqual(result.replacedHealthWorkoutUUIDs, [oldUUID])
        XCTAssertEqual(try context.fetch(FetchDescriptor<RideModel>()).count, 1)
    }

    /// 与 manualRide 同窗口、但作为自动检测保存的带轨迹 Ride。
    private func manualRideAsAuto() -> Ride {
        let base = manualRide()
        return Ride(activityType: base.activityType, start: base.start, end: base.end, source: .merged,
                    distanceMeters: base.distanceMeters, avgSpeedMps: base.avgSpeedMps,
                    calories: base.calories, confidence: 2, route: base.route)
    }
}
