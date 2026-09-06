import XCTest
@testable import CyclingDomain

final class WatchHeartRateTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_700_000_000)

    private func at(_ seconds: TimeInterval) -> Date { t0.addingTimeInterval(seconds) }

    // MARK: - 新鲜度

    func testFreshReadingIsLive() {
        let reading = WatchHeartRate(bpm: 132, measuredAt: t0)
        XCTAssertEqual(reading.freshness(at: at(0)), .live)
        XCTAssertEqual(reading.freshness(at: at(19)), .live)
    }

    func testReadingOlderThanLiveWindowIsRecentNotLive() {
        let reading = WatchHeartRate(bpm: 132, measuredAt: t0)
        XCTAssertEqual(reading.freshness(at: at(20)), .recent)
        XCTAssertEqual(reading.freshness(at: at(15 * 60)), .recent)
    }

    /// 半小时前的心率跟「现在在骑车」没关系，不该继续显示成当前心率。
    func testVeryOldReadingIsStale() {
        let reading = WatchHeartRate(bpm: 132, measuredAt: t0)
        XCTAssertEqual(reading.freshness(at: at(15 * 60 + 1)), .stale)
        XCTAssertEqual(reading.freshness(at: at(3600)), .stale)
    }

    /// 手表时钟可能比手机快一两秒，时间戳落在未来不该被判成过期。
    func testFutureTimestampCountsAsLive() {
        let reading = WatchHeartRate(bpm: 132, measuredAt: at(5))
        XCTAssertEqual(reading.freshness(at: t0), .live)
    }

    // MARK: - 两个来源取更新的

    /// 手表推送即时到达，HealthKit 里的同一批样本要等系统后台回写。
    /// 所以「后到的」不一定「更新」，必须按测量时间比。
    func testFresherPicksLaterMeasurement() {
        let watch = WatchHeartRate(bpm: 140, measuredAt: at(100))
        let healthKit = WatchHeartRate(bpm: 120, measuredAt: at(40))
        XCTAssertEqual(WatchHeartRate.fresher(watch, healthKit), watch)
        XCTAssertEqual(WatchHeartRate.fresher(healthKit, watch), watch)
    }

    func testFresherHandlesMissingSources() {
        let reading = WatchHeartRate(bpm: 140, measuredAt: at(100))
        XCTAssertEqual(WatchHeartRate.fresher(reading, nil), reading)
        XCTAssertEqual(WatchHeartRate.fresher(nil, reading), reading)
        XCTAssertNil(WatchHeartRate.fresher(nil, nil))
    }

    // MARK: - 传输

    func testRoundTripsThroughJSON() throws {
        let reading = WatchHeartRate(bpm: 132.5, measuredAt: t0)
        let data = try JSONEncoder().encode(reading)
        XCTAssertEqual(try JSONDecoder().decode(WatchHeartRate.self, from: data), reading)
    }
}
