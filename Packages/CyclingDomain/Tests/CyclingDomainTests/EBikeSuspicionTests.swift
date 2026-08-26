import XCTest
@testable import CyclingDomain

final class EBikeSuspicionTests: XCTestCase {

    // MARK: - 造样本

    /// 匀速样本：均值 meanKmh，围绕均值 ±jitterKmh 交替抖动。
    private func samples(count: Int, meanKmh: Double, jitterKmh: Double = 0) -> [Double] {
        (0..<count).map { i in
            let sign = i.isMultiple(of: 2) ? 1.0 : -1.0
            return (meanKmh + sign * jitterKmh) / 3.6
        }
    }

    // MARK: - 命中：典型电动车

    func test_steadyHighSpeed_longRide_isSuspected() {
        // 匀速 22 km/h、低抖动、10 分钟 → 疑似电动车
        let s = samples(count: 120, meanKmh: 22, jitterKmh: 1)
        XCTAssertTrue(isSuspectedEBike(activityType: .cycling, durationSeconds: 600, speedSamplesMps: s))
    }

    // MARK: - 不命中

    func test_variablePedaling_isNotSuspected() {
        // 起伏蹬踏：10→34 km/h 反复加减速 + 停顿。均速 22 km/h 过速度门槛，
        // 但 CV ≈ 0.35 > 0.30 → 专测方差闸门拦下真骑行。
        let pedaling: [Double] = (0..<120).map { i in
            let phase = Double(i % 12)
            if phase < 2 { return 0.3 }                     // 等红灯（被剔除）
            return (10 + (phase - 2) * 24 / 9) / 3.6        // 10→34 km/h 爬升
        }
        XCTAssertFalse(isSuspectedEBike(activityType: .cycling, durationSeconds: 600, speedSamplesMps: pedaling))
    }

    func test_shortRide_isNotSuspected() {
        // 高速匀速但 < 5 分钟 → 样本不足，不判
        let s = samples(count: 60, meanKmh: 25, jitterKmh: 0.5)
        XCTAssertFalse(isSuspectedEBike(activityType: .cycling, durationSeconds: 299, speedSamplesMps: s))
    }

    func test_noGPSSamples_isNotSuspected() {
        // motionOnly 无轨迹 → 不判
        XCTAssertFalse(isSuspectedEBike(activityType: .cycling, durationSeconds: 1200, speedSamplesMps: []))
    }

    func test_nonCycling_isNotSuspected() {
        // 跑步即使速度稳定也不判（只针对骑行）
        let s = samples(count: 120, meanKmh: 22, jitterKmh: 1)
        XCTAssertFalse(isSuspectedEBike(activityType: .running, durationSeconds: 600, speedSamplesMps: s))
        XCTAssertFalse(isSuspectedEBike(activityType: .walking, durationSeconds: 600, speedSamplesMps: s))
        XCTAssertFalse(isSuspectedEBike(activityType: .other, durationSeconds: 600, speedSamplesMps: s))
    }

    func test_slowSteadyRide_isNotSuspected() {
        // 匀速但只有 15 km/h（< 20 km/h 门槛）→ 慢骑不判
        let s = samples(count: 120, meanKmh: 15, jitterKmh: 0.5)
        XCTAssertFalse(isSuspectedEBike(activityType: .cycling, durationSeconds: 600, speedSamplesMps: s))
    }

    func test_allStoppedSamples_isNotSuspected() {
        // 全是停顿样本（≤ 移动阈值）→ 移动样本不足，不判
        let stopped = Array(repeating: 1.0, count: 120)
        XCTAssertFalse(isSuspectedEBike(activityType: .cycling, durationSeconds: 600, speedSamplesMps: stopped))
    }

    // MARK: - 边界取等（含边界 → 命中）

    func test_boundary_durationExactly300_counts() {
        let s = samples(count: 120, meanKmh: 22, jitterKmh: 1)
        XCTAssertTrue(isSuspectedEBike(activityType: .cycling, durationSeconds: 300, speedSamplesMps: s))
    }

    func test_boundary_meanExactlyMinAvgSpeed_counts() {
        // 均速恰好 = minAvgSpeedMps（零方差）→ 命中
        let s = Array(repeating: EBikeHeuristic.minAvgSpeedMps, count: 120)
        XCTAssertTrue(isSuspectedEBike(activityType: .cycling, durationSeconds: 600, speedSamplesMps: s))
    }

    func test_cvJustBelowMax_counts() {
        // CV 边界语义为 <=（含边界命中），但 0.30 在二进制浮点不可精确表示，
        // 取等无法稳定测试；用近边界对钉住行为：CV ≈ 0.29 → 命中。
        // （一半 m(1±d)：均值 m、标准差 dm → CV = d；低值 m*0.71=4.97 仍 > 移动阈值 1.4）
        let m = 7.0  // m/s ≈ 25 km/h，高于均速门槛
        let s: [Double] = (0..<120).map { $0.isMultiple(of: 2) ? m * 1.29 : m * 0.71 }
        XCTAssertTrue(isSuspectedEBike(activityType: .cycling, durationSeconds: 600, speedSamplesMps: s))
    }

    func test_cvJustAboveMax_isNotSuspected() {
        // CV ≈ 0.31 略超 → 不判
        let m = 7.0
        let s: [Double] = (0..<120).map { $0.isMultiple(of: 2) ? m * 1.31 : m * 0.69 }
        XCTAssertFalse(isSuspectedEBike(activityType: .cycling, durationSeconds: 600, speedSamplesMps: s))
    }

    func test_stopsAreIgnored_steadyMovingStillSuspected() {
        // 电动车也会等红灯：停顿样本被剔除后，移动部分依旧匀速高速 → 仍命中
        let s: [Double] = (0..<120).map { i in
            i % 10 < 2 ? 0.5 : 22 / 3.6   // 20% 时间停着，其余匀速 22 km/h
        }
        XCTAssertTrue(isSuspectedEBike(activityType: .cycling, durationSeconds: 600, speedSamplesMps: s))
    }
}
