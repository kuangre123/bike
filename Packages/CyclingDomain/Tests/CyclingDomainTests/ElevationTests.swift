import XCTest
@testable import CyclingDomain

final class ElevationTests: XCTestCase {
    func test_monotonicClimb_sumsFully() {
        // 10 → 60 米持续爬升：滞回累计到阈值触发，总爬升不丢 → 50
        let alts = stride(from: 10.0, through: 60.0, by: 5.0).map { $0 }
        XCTAssertEqual(elevationGainMeters(altitudes: alts), 50, accuracy: 0.001)
    }

    func test_noisyFlat_isZero() {
        // 平路 ±4 米抖动（峰谷差 8 < 阈值 10）→ 爬升 0
        let alts: [Double] = (0..<50).map { 100 + ($0.isMultiple(of: 2) ? 4.0 : -4.0) }
        XCTAssertEqual(elevationGainMeters(altitudes: alts), 0, accuracy: 0.001)
    }

    func test_pureDescent_isZero() {
        let alts = stride(from: 200.0, through: 100.0, by: -10.0).map { $0 }
        XCTAssertEqual(elevationGainMeters(altitudes: alts), 0, accuracy: 0.001)
    }

    func test_rollingHills_sumsOnlyClimbs() {
        // 100 →(+30) 130 →(-20) 110 →(+40) 150：爬升 = 30 + 40 = 70
        // （±10 段变化 ≥ 阈值 10，取等触发）
        let alts: [Double] = [100, 110, 120, 130, 120, 110, 125, 140, 150]
        XCTAssertEqual(elevationGainMeters(altitudes: alts), 70, accuracy: 0.001)
    }

    func test_gentleClimb_accumulatesViaHysteresis() {
        // 每步 +2 的缓坡：单步不过阈值，但相对基准累到 10 触发一次；
        // 0→20 全程计入 20，缓坡不丢。
        let alts = stride(from: 0.0, through: 20.0, by: 2.0).map { $0 }
        XCTAssertEqual(elevationGainMeters(altitudes: alts), 20, accuracy: 0.001)
    }

    func test_emptyAndSingle_areZero() {
        XCTAssertEqual(elevationGainMeters(altitudes: []), 0)
        XCTAssertEqual(elevationGainMeters(altitudes: [123]), 0)
    }
}
