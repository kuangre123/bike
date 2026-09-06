import XCTest
@testable import CyclingDomain

final class ActiveTimeTrackerTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_700_000_000)

    private func at(_ seconds: TimeInterval) -> Date { t0.addingTimeInterval(seconds) }

    // MARK: - 基本计时

    func testClockAdvancesWithWallClock() {
        let tracker = ActiveTimeTracker(startDate: t0)
        XCTAssertEqual(tracker.activeDuration(at: at(30)), 30, accuracy: 0.001)
        XCTAssertEqual(tracker.activeDuration(at: at(600)), 600, accuracy: 0.001)
    }

    func testManualPauseFreezesAndResumeContinues() {
        var tracker = ActiveTimeTracker(startDate: t0)
        tracker.manualPause(at: at(30))
        XCTAssertFalse(tracker.isRunning)
        XCTAssertEqual(tracker.activeDuration(at: at(200)), 30, accuracy: 0.001)
        tracker.manualResume(at: at(200))
        XCTAssertEqual(tracker.activeDuration(at: at(210)), 40, accuracy: 0.001)
    }

    // MARK: - 停等（有定位回调）

    func testSustainedLowSpeedFreezesClock() {
        var tracker = ActiveTimeTracker(startDate: t0)
        tracker.ingestLocation(timestamp: at(10), speedMps: 4, armed: true)
        for s in stride(from: 20.0, through: 26.0, by: 1.0) {
            tracker.ingestLocation(timestamp: at(s), speedMps: 0.2, armed: true)
        }
        XCTAssertTrue(tracker.isAutoPaused)
        // 低速起点 20s，满 5s（25s）时冻结。
        XCTAssertEqual(tracker.activeDuration(at: at(300)), 25, accuracy: 0.001)
    }

    func testMovingAgainResumesClock() {
        var tracker = ActiveTimeTracker(startDate: t0)
        tracker.ingestLocation(timestamp: at(10), speedMps: 4, armed: true)
        for s in stride(from: 20.0, through: 26.0, by: 1.0) {
            tracker.ingestLocation(timestamp: at(s), speedMps: 0.2, armed: true)
        }
        tracker.ingestLocation(timestamp: at(120), speedMps: 3, armed: true)
        XCTAssertFalse(tracker.isAutoPaused)
        XCTAssertEqual(tracker.activeDuration(at: at(130)), 35, accuracy: 0.001)
    }

    func testNotArmedNeverAutoPauses() {
        var tracker = ActiveTimeTracker(startDate: t0)
        for s in stride(from: 1.0, through: 60.0, by: 1.0) {
            tracker.ingestLocation(timestamp: at(s), speedMps: 0, armed: false)
        }
        XCTAssertFalse(tracker.isAutoPaused)
        XCTAssertEqual(tracker.activeDuration(at: at(60)), 60, accuracy: 0.001)
    }

    // MARK: - 回归：等红灯时定位断流

    /// 停住不动时 iOS 往往不再回调定位（距离过滤 / 系统节流），
    /// 只靠定位驱动的状态机永远判不出这次停等，整段等待被算进骑行时长。
    func testStallWithoutLocationUpdatesFreezesClock() {
        var tracker = ActiveTimeTracker(startDate: t0)
        tracker.ingestLocation(timestamp: at(10), speedMps: 4, armed: true)
        tracker.ingestLocation(timestamp: at(30), speedMps: 4, armed: true)

        // 30s 后停下，之后 120 秒一个定位都没来，只有 UI 的每秒心跳。
        for s in stride(from: 31.0, through: 150.0, by: 1.0) {
            tracker.tick(at: at(s), armed: true)
        }

        XCTAssertTrue(tracker.isAutoPaused, "定位断流超过阈值应按停等冻结")
        XCTAssertEqual(tracker.activeDuration(at: at(150)), 30, accuracy: 0.001,
                       "等待的 120 秒不该算进骑行时长")
    }

    /// 静止时 GPS 常年报 speed = -1（无效）。这类定位不能算作「有速度数据」，
    /// 否则会一直刷新断流计时，停等永远判不出来。
    func testInvalidSpeedFixesDoNotKeepClockRunning() {
        var tracker = ActiveTimeTracker(startDate: t0)
        tracker.ingestLocation(timestamp: at(10), speedMps: 4, armed: true)
        tracker.ingestLocation(timestamp: at(30), speedMps: 4, armed: true)

        for s in stride(from: 31.0, through: 150.0, by: 1.0) {
            tracker.ingestLocation(timestamp: at(s), speedMps: -1, armed: true)
            tracker.tick(at: at(s), armed: true)
        }

        XCTAssertTrue(tracker.isAutoPaused)
        XCTAssertEqual(tracker.activeDuration(at: at(150)), 30, accuracy: 0.001)
    }

    func testTickDoesNotFreezeWhileLocationsKeepArriving() {
        var tracker = ActiveTimeTracker(startDate: t0)
        for s in stride(from: 1.0, through: 60.0, by: 1.0) {
            tracker.ingestLocation(timestamp: at(s), speedMps: 5, armed: true)
            tracker.tick(at: at(s), armed: true)
        }
        XCTAssertFalse(tracker.isAutoPaused)
        XCTAssertEqual(tracker.activeDuration(at: at(60)), 60, accuracy: 0.001)
    }

    // MARK: - 回归：预热窗口只算一次

    /// 预热窗口用于丢掉刚开机的粗糙定位，整段会话只该算一次。
    /// 若跟着每次停等恢复重置，市区走走停停会把每次起步后的 8 秒轨迹全丢掉，
    /// 距离和均速被严重低估（2 分钟骑行只剩 65 米、1.6 公里/时）。
    func testWarmupIsMeasuredOncePerSessionNotAfterEveryResume() {
        var tracker = ActiveTimeTracker(startDate: t0)
        XCTAssertFalse(tracker.isWarmedUp(at: at(5)))
        XCTAssertTrue(tracker.isWarmedUp(at: at(9)))

        tracker.ingestLocation(timestamp: at(10), speedMps: 4, armed: true)
        for s in stride(from: 20.0, through: 26.0, by: 1.0) {
            tracker.ingestLocation(timestamp: at(s), speedMps: 0.2, armed: true)
        }
        XCTAssertTrue(tracker.isAutoPaused)
        tracker.ingestLocation(timestamp: at(300), speedMps: 3, armed: true)
        XCTAssertFalse(tracker.isAutoPaused)

        XCTAssertTrue(tracker.isWarmedUp(at: at(301)), "停等恢复后不该重新预热")
    }

    func testManualResumeDoesNotRestartWarmup() {
        var tracker = ActiveTimeTracker(startDate: t0)
        tracker.manualPause(at: at(30))
        tracker.manualResume(at: at(300))
        XCTAssertTrue(tracker.isWarmedUp(at: at(301)))
    }

    func testStartResetsEverything() {
        var tracker = ActiveTimeTracker(startDate: t0)
        tracker.ingestLocation(timestamp: at(10), speedMps: 4, armed: true)
        tracker.manualPause(at: at(30))

        tracker.start(at: at(1000))
        XCTAssertFalse(tracker.isManuallyPaused)
        XCTAssertFalse(tracker.isAutoPaused)
        XCTAssertTrue(tracker.isRunning)
        XCTAssertEqual(tracker.activeDuration(at: at(1010)), 10, accuracy: 0.001)
        XCTAssertFalse(tracker.isWarmedUp(at: at(1005)))
        XCTAssertTrue(tracker.isWarmedUp(at: at(1009)))
    }
}
