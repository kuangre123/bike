import XCTest
@testable import CyclingDomain

final class ExternalWorkoutImportTests: XCTestCase {
    private let base = Date(timeIntervalSince1970: 1_700_000_000)
    private let garmin = ExternalWorkoutSource(id: "com.garmin.connect.mobile", name: "Garmin Connect")
    private let zepp = ExternalWorkoutSource(id: "com.huami.zeppLife", name: "Zepp")

    private func workout(
        _ source: ExternalWorkoutSource,
        id: UUID = UUID(),
        type: ActivityType = .cycling,
        offsetMinutes: Double = 0,
        durationMinutes: Double = 30,
        distanceMeters: Double? = 12_000,
        calories: Double? = 300,
        avgHeartRate: Double? = 132,
        route: [GPSSample] = []
    ) -> ExternalWorkout {
        let start = base.addingTimeInterval(offsetMinutes * 60)
        return ExternalWorkout(
            id: id,
            source: source,
            activityType: type,
            start: start,
            end: start.addingTimeInterval(durationMinutes * 60),
            distanceMeters: distanceMeters,
            calories: calories,
            avgHeartRate: avgHeartRate,
            route: route
        )
    }

    // MARK: - 筛选

    func testOnlyEnabledSourcesAreImported() {
        let picked = ExternalWorkoutImport.importable(
            [workout(garmin), workout(zepp)],
            enabledSourceIDs: [garmin.id],
            alreadyImported: [],
            dismissed: []
        )
        XCTAssertEqual(picked.map(\.source.id), [garmin.id])
    }

    func testNoEnabledSourcesImportsNothing() {
        let picked = ExternalWorkoutImport.importable(
            [workout(garmin), workout(zepp)],
            enabledSourceIDs: [],
            alreadyImported: [],
            dismissed: []
        )
        XCTAssertTrue(picked.isEmpty)
    }

    func testAlreadyImportedWorkoutIsNotImportedAgain() {
        let existing = UUID()
        let picked = ExternalWorkoutImport.importable(
            [workout(garmin, id: existing), workout(garmin, offsetMinutes: 120)],
            enabledSourceIDs: [garmin.id],
            alreadyImported: [existing],
            dismissed: []
        )
        XCTAssertEqual(picked.count, 1)
        XCTAssertNotEqual(picked[0].id, existing)
    }

    /// 用户删掉过的外部运动不能在下次导入时自己长回来。
    func testDismissedWorkoutIsNotReimported() {
        let deleted = UUID()
        let picked = ExternalWorkoutImport.importable(
            [workout(garmin, id: deleted)],
            enabledSourceIDs: [garmin.id],
            alreadyImported: [],
            dismissed: [deleted]
        )
        XCTAssertTrue(picked.isEmpty)
    }

    func testTooShortWorkoutIsSkipped() {
        let picked = ExternalWorkoutImport.importable(
            [workout(garmin, durationMinutes: 1)],
            enabledSourceIDs: [garmin.id],
            alreadyImported: [],
            dismissed: []
        )
        XCTAssertTrue(picked.isEmpty)
    }

    /// 步行的最小时长比骑行长，沿用检测管线同一套阈值。
    func testWalkingUsesItsOwnMinimumDuration() {
        let threeMinuteWalk = workout(garmin, type: .walking, durationMinutes: 3)
        let threeMinuteRide = workout(garmin, type: .cycling, durationMinutes: 3)
        let picked = ExternalWorkoutImport.importable(
            [threeMinuteWalk, threeMinuteRide],
            enabledSourceIDs: [garmin.id],
            alreadyImported: [],
            dismissed: []
        )
        XCTAssertEqual(picked.map(\.activityType), [.cycling])
    }

    func testResultIsSortedByStartDate() {
        let later = workout(garmin, offsetMinutes: 600)
        let earlier = workout(garmin, offsetMinutes: 0)
        let picked = ExternalWorkoutImport.importable(
            [later, earlier],
            enabledSourceIDs: [garmin.id],
            alreadyImported: [],
            dismissed: []
        )
        XCTAssertEqual(picked.map(\.start), [earlier.start, later.start])
    }

    // MARK: - 映射

    func testMappingCarriesMeasuredValues() {
        let ride = ExternalWorkoutImport.ride(from: workout(garmin))
        XCTAssertEqual(ride.activityType, .cycling)
        XCTAssertEqual(ride.source, .externalImport)
        XCTAssertEqual(ride.distanceMeters, 12_000)
        XCTAssertEqual(ride.calories, 300)
        XCTAssertEqual(ride.avgHeartRate, 132)
        XCTAssertEqual(ride.duration, 30 * 60)
        XCTAssertNil(ride.activeDuration, "外部记录只有起止时间，没有暂停信息")
    }

    func testAverageSpeedIsDerivedFromRecordedDistance() {
        let ride = ExternalWorkoutImport.ride(from: workout(garmin, durationMinutes: 30, distanceMeters: 9_000))
        XCTAssertEqual(try XCTUnwrap(ride.avgSpeedMps), 5.0, accuracy: 0.0001)
    }

    /// 设备没记距离就不猜距离，均速也留空——不造数。
    func testMissingDistanceLeavesSpeedNil() {
        let ride = ExternalWorkoutImport.ride(from: workout(garmin, distanceMeters: nil))
        XCTAssertNil(ride.distanceMeters)
        XCTAssertNil(ride.avgSpeedMps)
    }

    func testZeroDurationDoesNotProduceInfiniteSpeed() {
        let ride = ExternalWorkoutImport.ride(from: workout(garmin, durationMinutes: 0, distanceMeters: 500))
        XCTAssertNil(ride.avgSpeedMps)
    }

    func testRouteIsCarriedOver() {
        let samples = [
            GPSSample(timestamp: base, latitude: 31.2, longitude: 121.4, speedMps: 5),
            GPSSample(timestamp: base.addingTimeInterval(60), latitude: 31.21, longitude: 121.41, speedMps: 6)
        ]
        let ride = ExternalWorkoutImport.ride(from: workout(garmin, route: samples))
        XCTAssertEqual(ride.route, samples)
    }

    func testEmptyRouteBecomesNilNotEmptyArray() {
        let ride = ExternalWorkoutImport.ride(from: workout(garmin, route: []))
        XCTAssertNil(ride.route)
    }

    // MARK: - 删除墓碑

    func testDismissedListDropsOldestBeyondLimit() {
        let existing = (0..<5).map { _ in UUID() }
        let fresh = UUID()
        let trimmed = ExternalWorkoutImport.appendingDismissed(existing, fresh, limit: 5)
        XCTAssertEqual(trimmed.count, 5)
        XCTAssertEqual(trimmed.last, fresh)
        XCTAssertFalse(trimmed.contains(existing[0]), "超出上限时丢最旧的")
    }

    func testDismissedListDoesNotDuplicate() {
        let id = UUID()
        let trimmed = ExternalWorkoutImport.appendingDismissed([id], id, limit: 5)
        XCTAssertEqual(trimmed, [id])
    }
}
