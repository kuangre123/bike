import XCTest
import CyclingDomain
@testable import Bike

final class ActivityRecordingPreferencesTests: XCTestCase {

    /// 匀速高速样本（命中疑似电动车）。
    private func steadyFastSamples() -> [Double] {
        Array(repeating: 6.1, count: 120)  // ≈22 km/h 零方差
    }
    /// 起伏样本（不像电动车）。
    private func variableSamples() -> [Double] {
        (0..<120).map { $0.isMultiple(of: 2) ? 3.0 : 8.0 }
    }

    private func decide(
        _ type: ActivityType,
        samples: [Double] = [],
        walking: Bool = true, ebike: Bool = true, other: Bool = true,
        duration: TimeInterval = 600
    ) -> Bool {
        ActivityRecordingPreferences.shouldRecord(
            activityType: type, durationSeconds: duration, speedSamplesMps: samples,
            recordWalking: walking, recordEBike: ebike, recordOther: other
        )
    }

    func test_allOn_recordsEverything() {
        XCTAssertTrue(decide(.walking))
        XCTAssertTrue(decide(.running))
        XCTAssertTrue(decide(.cycling, samples: steadyFastSamples()))
        XCTAssertTrue(decide(.other))
    }

    func test_walkingOff_skipsWalkingOnly() {
        XCTAssertFalse(decide(.walking, walking: false))
        XCTAssertTrue(decide(.running, walking: false))
        XCTAssertTrue(decide(.cycling, samples: variableSamples(), walking: false))
    }

    func test_otherOff_skipsOtherOnly() {
        XCTAssertFalse(decide(.other, other: false))
        XCTAssertTrue(decide(.walking, other: false))
    }

    func test_runningAndCyclingAlwaysRecorded_regardlessOfToggles() {
        XCTAssertTrue(decide(.running, walking: false, ebike: false, other: false))
        XCTAssertTrue(decide(.cycling, samples: variableSamples(), walking: false, ebike: false, other: false))
    }

    func test_ebikeOff_skipsSuspectedCyclingButKeepsNormalCycling() {
        // 关闭电动车：疑似电动车骑行不记录，普通起伏骑行照常记录
        XCTAssertFalse(decide(.cycling, samples: steadyFastSamples(), ebike: false))
        XCTAssertTrue(decide(.cycling, samples: variableSamples(), ebike: false))
    }

    func test_ebikeOff_noGPS_stillRecords() {
        // 无 GPS 轨迹判不出电动车 → 保守保留（即使关了电动车）
        XCTAssertTrue(decide(.cycling, samples: [], ebike: false))
    }

    func test_ebikeOn_recordsSuspectedCycling() {
        // 电动车开关开着：即便疑似电动车也照常记录（后续可手动排除）
        XCTAssertTrue(decide(.cycling, samples: steadyFastSamples(), ebike: true))
    }
}
