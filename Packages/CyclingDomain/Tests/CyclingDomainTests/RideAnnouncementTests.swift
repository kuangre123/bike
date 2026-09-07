import XCTest
@testable import CyclingDomain

final class RideAnnouncementTests: XCTestCase {

    private func tracker() -> AnnouncementTracker { AnnouncementTracker() }

    // MARK: - 时长里程碑

    func testNothingBeforeFirstMilestone() {
        var t = tracker()
        XCTAssertNil(t.advance(durationSeconds: 9 * 60, distanceMeters: 100))
    }

    func testAnnouncesAtTenMinutes() {
        var t = tracker()
        let a = t.advance(durationSeconds: 10 * 60, distanceMeters: 3000)
        XCTAssertEqual(a?.durationSeconds, 600)
    }

    func testSameMilestoneAnnouncedOnlyOnce() {
        var t = tracker()
        XCTAssertNotNil(t.advance(durationSeconds: 10 * 60, distanceMeters: 3000))
        XCTAssertNil(t.advance(durationSeconds: 10 * 60 + 1, distanceMeters: 3010))
        // 距离要停在 5 公里以内，否则越的是距离里程碑、本来就该播
        XCTAssertNil(t.advance(durationSeconds: 19 * 60, distanceMeters: 4000))
    }

    func testAnnouncesAgainAtNextMilestone() {
        var t = tracker()
        _ = t.advance(durationSeconds: 10 * 60, distanceMeters: 3000)
        XCTAssertNotNil(t.advance(durationSeconds: 20 * 60, distanceMeters: 6000))
    }

    /// app 被切到后台再回来时，中间跨过的里程碑不该一次补播好几条。
    func testSkippedMilestonesAnnounceOnlyOnce() {
        var t = tracker()
        XCTAssertNotNil(t.advance(durationSeconds: 35 * 60, distanceMeters: 10_000))
        XCTAssertNil(t.advance(durationSeconds: 35 * 60 + 5, distanceMeters: 10_010))
        // 下一次要等 40 分钟，而不是补 10/20/30
        XCTAssertNil(t.advance(durationSeconds: 39 * 60, distanceMeters: 11_000))
        XCTAssertNotNil(t.advance(durationSeconds: 40 * 60, distanceMeters: 12_000))
    }

    /// 暂停时有效时长不涨，不该反复播报。
    func testPausedRideDoesNotRepeat() {
        var t = tracker()
        XCTAssertNotNil(t.advance(durationSeconds: 10 * 60, distanceMeters: 3000))
        for _ in 0..<10 {
            XCTAssertNil(t.advance(durationSeconds: 10 * 60, distanceMeters: 3000))
        }
    }

    // MARK: - 距离里程碑

    func testAnnouncesAtFiveKilometers() {
        var t = tracker()
        XCTAssertNotNil(t.advance(durationSeconds: 5 * 60, distanceMeters: 5000))
    }

    func testDistanceMilestoneNotRepeated() {
        var t = tracker()
        XCTAssertNotNil(t.advance(durationSeconds: 5 * 60, distanceMeters: 5000))
        XCTAssertNil(t.advance(durationSeconds: 6 * 60, distanceMeters: 7000))
        XCTAssertNotNil(t.advance(durationSeconds: 7 * 60, distanceMeters: 10_000))
    }

    /// 时长和距离同时越线时只播一次——播报内容本来就包含全部数据，播两遍是噪声。
    func testSimultaneousMilestonesAnnounceOnce() {
        var t = tracker()
        XCTAssertNotNil(t.advance(durationSeconds: 10 * 60, distanceMeters: 5000))
        XCTAssertNil(t.advance(durationSeconds: 10 * 60 + 1, distanceMeters: 5001))
    }

    // MARK: - 没有可信数据时不硬凑

    /// GPS 没动就没有距离，也就没有均速——不拿 0 冒充。
    func testNoDistanceDataAnnouncesDurationOnly() {
        var t = tracker()
        let a = t.advance(durationSeconds: 10 * 60, distanceMeters: nil)
        XCTAssertEqual(a?.durationSeconds, 600)
        XCTAssertNil(a?.distanceMeters)
        XCTAssertNil(a?.avgSpeedMps)
    }

    func testZeroDistanceIsReportedAsZeroNotAsMissing() {
        var t = tracker()
        let a = t.advance(durationSeconds: 10 * 60, distanceMeters: 0)
        XCTAssertEqual(a?.distanceMeters, 0)
        XCTAssertEqual(a?.avgSpeedMps, 0)
    }

    func testAverageSpeedIsDistanceOverDuration() {
        var t = tracker()
        let a = t.advance(durationSeconds: 600, distanceMeters: 3000)
        XCTAssertEqual(a?.avgSpeedMps ?? 0, 5, accuracy: 0.001)   // 3000m / 600s
    }

    func testZeroDurationDoesNotProduceInfiniteSpeed() {
        var t = tracker()
        // 距离先到（GPS 跳变），时长还是 0
        let a = t.advance(durationSeconds: 0, distanceMeters: 5000)
        XCTAssertNil(a?.avgSpeedMps)
    }

    func testNegativeDistanceIsTreatedAsMissing() {
        var t = tracker()
        let a = t.advance(durationSeconds: 10 * 60, distanceMeters: -5)
        XCTAssertNil(a?.distanceMeters)
        XCTAssertNil(a?.avgSpeedMps)
    }

    // MARK: - 自定义间隔

    func testCustomIntervals() {
        var t = AnnouncementTracker(durationIntervalMinutes: 5, distanceIntervalKilometers: 1)
        XCTAssertNotNil(t.advance(durationSeconds: 5 * 60, distanceMeters: 500))
        XCTAssertNotNil(t.advance(durationSeconds: 6 * 60, distanceMeters: 1000))
    }

    /// 间隔配成 0 时不能除零，也不能变成每次都播。
    func testZeroIntervalDoesNotCrashOrSpam() {
        var t = AnnouncementTracker(durationIntervalMinutes: 0, distanceIntervalKilometers: 0)
        XCTAssertNil(t.advance(durationSeconds: 10 * 60, distanceMeters: 5000))
        XCTAssertNil(t.advance(durationSeconds: 20 * 60, distanceMeters: 10_000))
    }
}
