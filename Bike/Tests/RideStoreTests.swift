import XCTest
import SwiftData
import CyclingDomain
@testable import Bike

/// RideStore 去重规则：手动实录 / 第三方导入 / 自动检测三者的胜负关系。
/// 强弱：manual > externalImport > autoDetected。
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

        let result = try RideStore(context: context).save([manualRide()], provenance: .manual)

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

        let result = try RideStore(context: context).save([manualRide()], provenance: .manual)

        XCTAssertEqual(result.inserted.count, 1)
        XCTAssertTrue(result.replacedHealthWorkoutUUIDs.isEmpty)
        XCTAssertEqual(try context.fetch(FetchDescriptor<RideModel>()).count, 2, "轻微边界重叠应共存")
    }

    func test_manualRide_blockedByOverlappingManualRecord() throws {
        let context = try makeContext()
        insertModel(context, start: 0, end: 900, auto: false)  // 已有手动记录

        let result = try RideStore(context: context).save([manualRide()], provenance: .manual)

        XCTAssertTrue(result.inserted.isEmpty, "不得覆盖已有手动记录")
        XCTAssertEqual(try context.fetch(FetchDescriptor<RideModel>()).count, 1)
    }

    func test_autoRide_neverReplacesManualRecord() throws {
        let context = try makeContext()
        insertModel(context, start: 0, end: 1080, auto: false, healthUUID: UUID())

        let auto = Ride(activityType: .cycling, start: date(0), end: date(900), source: .motionOnly,
                        distanceMeters: nil, avgSpeedMps: nil, calories: nil, confidence: 1)
        let result = try RideStore(context: context).save([auto], provenance: .autoDetected)

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
        let result = try RideStore(context: context).save([upgraded], provenance: .autoDetected)

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

    // MARK: - 第三方导入（Garmin / 华为 / Zepp…）

    /// 与 manualRide 同窗口的第三方记录，模拟 Garmin 写进 Apple 健康的那条 workout。
    private func externalWorkout(
        id: UUID = UUID(), start: TimeInterval = 0, end: TimeInterval = 1080
    ) -> ExternalWorkout {
        ExternalWorkout(
            id: id,
            source: ExternalWorkoutSource(id: "com.garmin.connect.mobile", name: "Garmin Connect"),
            activityType: .cycling,
            start: date(start), end: date(end),
            distanceMeters: 2400, calories: 95, avgHeartRate: 132,
            route: [GPSSample(timestamp: date(start), latitude: 31.23, longitude: 121.47, speedMps: 2)]
        )
    }

    /// 设备实测顶掉本 app 的估算记录；但只上报**我们自己**写的 workout 供删除。
    /// 这条是安全底线：把第三方 UUID 混进 replacedHealthWorkoutUUIDs 会删掉用户的 Garmin 数据。
    func test_import_replacesAutoRecord_andReportsOnlyOurOwnHealthUUID() throws {
        let context = try makeContext()
        let ourWorkout = UUID()
        insertModel(context, start: 0, end: 900, auto: true, healthUUID: ourWorkout)

        let workout = externalWorkout()
        let result = try RideStore(context: context).saveImported([workout])

        XCTAssertEqual(result.inserted.count, 1, "设备实测应顶掉本 app 的估算记录")
        XCTAssertEqual(result.replacedHealthWorkoutUUIDs, [ourWorkout],
                       "只上报我们自己写的 workout；第三方那条不归我们删")
        let saved = try XCTUnwrap(result.inserted.first)
        XCTAssertEqual(saved.externalWorkoutUUID, workout.id)
        XCTAssertEqual(saved.externalSourceName, "Garmin Connect")
        XCTAssertNil(saved.healthKitWorkoutUUID,
                     "第三方 workout UUID 绝不能存进「删除时会连带删掉」的字段")
    }

    func test_import_blockedByOverlappingManualRecord() throws {
        let context = try makeContext()
        insertModel(context, start: 0, end: 1080, auto: false)

        let result = try RideStore(context: context).saveImported([externalWorkout()])

        XCTAssertTrue(result.inserted.isEmpty, "用户在本 app 的实录优先于外部导入")
        XCTAssertEqual(try context.fetch(FetchDescriptor<RideModel>()).count, 1)
    }

    func test_import_isIdempotent() throws {
        let context = try makeContext()
        let store = RideStore(context: context)
        let workout = externalWorkout()

        XCTAssertEqual(try store.saveImported([workout]).inserted.count, 1)
        XCTAssertTrue(try store.saveImported([workout]).inserted.isEmpty, "同一条不得重复导入")
        XCTAssertEqual(try context.fetch(FetchDescriptor<RideModel>()).count, 1)
        XCTAssertEqual(try store.importedExternalWorkoutUUIDs(), [workout.id])
    }

    func test_manualRide_replacesImportedRecord_withoutTouchingTheirWorkout() throws {
        let context = try makeContext()
        let store = RideStore(context: context)
        try store.saveImported([externalWorkout()])

        let result = try store.save([manualRide()], provenance: .manual)

        XCTAssertEqual(result.inserted.count, 1, "本 app 实录带暂停信息，比外部记录更准")
        XCTAssertTrue(result.replacedHealthWorkoutUUIDs.isEmpty,
                      "顶掉导入记录不得连带删除第三方在健康里的 workout")
        XCTAssertEqual(try context.fetch(FetchDescriptor<RideModel>()).count, 1)
    }

    func test_autoRide_neverReplacesImportedRecord() throws {
        let context = try makeContext()
        let store = RideStore(context: context)
        try store.saveImported([externalWorkout()])

        let auto = Ride(activityType: .cycling, start: date(0), end: date(900), source: .motionOnly,
                        distanceMeters: nil, avgSpeedMps: nil, calories: nil, confidence: 1)
        let result = try store.save([auto], provenance: .autoDetected)

        XCTAssertTrue(result.inserted.isEmpty, "本 app 的估算不得覆盖设备实测")
        let all = try context.fetch(FetchDescriptor<RideModel>())
        XCTAssertEqual(all.count, 1)
        XCTAssertNotNil(all[0].externalWorkoutUUID, "导入记录保持原样")
    }
}
