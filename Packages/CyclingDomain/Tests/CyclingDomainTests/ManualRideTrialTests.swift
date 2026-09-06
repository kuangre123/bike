import XCTest
@testable import CyclingDomain

final class ManualRideTrialTests: XCTestCase {

    // MARK: - 能不能开

    func testFirstUseIsFreeForNonSubscriber() {
        XCTAssertTrue(ManualRideTrial.isAllowed(isPro: false, usedCount: 0))
    }

    func testSecondUseIsBlockedForNonSubscriber() {
        XCTAssertFalse(ManualRideTrial.isAllowed(isPro: false, usedCount: 1))
    }

    func testSubscriberIsNeverBlocked() {
        XCTAssertTrue(ManualRideTrial.isAllowed(isPro: true, usedCount: 0))
        XCTAssertTrue(ManualRideTrial.isAllowed(isPro: true, usedCount: 1))
        XCTAssertTrue(ManualRideTrial.isAllowed(isPro: true, usedCount: 999))
    }

    /// 老用户升级上来时计数是 0，等于白送一次。这是有意的：
    /// 没有历史数据可依据，宁可多给也不要凭空判定别人已经用过。
    func testUpgradingUserWithNoRecordedCountGetsTheFreeUse() {
        XCTAssertTrue(ManualRideTrial.isAllowed(isPro: false, usedCount: 0))
    }

    /// UserDefaults 读不到 key 时是 0；负数只可能来自脏数据，不能因此判定「还能用无数次」。
    func testNegativeStoredCountIsTreatedAsUnused() {
        XCTAssertTrue(ManualRideTrial.isAllowed(isPro: false, usedCount: -3))
        XCTAssertEqual(ManualRideTrial.remainingFreeUses(usedCount: -3), 1)
    }

    // MARK: - 消耗

    func testConsumingIncrementsCount() {
        XCTAssertEqual(ManualRideTrial.consuming(0), 1)
        XCTAssertEqual(ManualRideTrial.consuming(1), 2)
    }

    func testConsumingClampsNegativeToOne() {
        XCTAssertEqual(ManualRideTrial.consuming(-5), 1)
    }

    /// 订阅用户每次保存也会走这里，计数会一直涨；不能溢出成负数，
    /// 否则退订后反而白得一次免费。
    func testConsumingSaturatesInsteadOfOverflowing() {
        XCTAssertEqual(ManualRideTrial.consuming(Int.max), Int.max)
    }

    // MARK: - 剩余次数（给 UI 文案用）

    func testRemainingFreeUsesBeforeAnyUse() {
        XCTAssertEqual(ManualRideTrial.remainingFreeUses(usedCount: 0), 1)
    }

    func testRemainingFreeUsesAfterConsuming() {
        XCTAssertEqual(ManualRideTrial.remainingFreeUses(usedCount: 1), 0)
    }

    func testRemainingFreeUsesNeverGoesNegative() {
        XCTAssertEqual(ManualRideTrial.remainingFreeUses(usedCount: 7), 0)
    }
}
