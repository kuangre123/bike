import XCTest
@testable import CyclingDomain

final class RouteRecordingHintTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    private func ride(
        auto: Bool = true, route: Bool = false, daysAgo: Double = 1
    ) -> RoutelessRideSample {
        RoutelessRideSample(
            isAutoDetected: auto, hasRoute: route,
            end: now.addingTimeInterval(-daysAgo * 24 * 3600))
    }

    // MARK: - 计数

    func testCountsAutoDetectedRidesWithoutRoute() {
        let rides = [ride(), ride(), ride()]
        XCTAssertEqual(RouteRecordingHint.routelessCount(rides, now: now), 3)
    }

    func testRidesWithRouteDoNotCount() {
        let rides = [ride(route: true), ride(route: true), ride()]
        XCTAssertEqual(RouteRecordingHint.routelessCount(rides, now: now), 1)
    }

    /// 手动码表骑行是前台运行的，缺轨迹另有原因，不能拿来当「该开始终定位」的证据。
    func testManualRidesDoNotCount() {
        let rides = [ride(auto: false), ride(auto: false), ride()]
        XCTAssertEqual(RouteRecordingHint.routelessCount(rides, now: now), 1)
    }

    /// 一年前的老记录不能算数——可能那时候还没授权，现在早就好了。
    func testOldRidesOutsideWindowDoNotCount() {
        let rides = [ride(daysAgo: 400), ride(daysAgo: 100), ride(daysAgo: 2)]
        XCTAssertEqual(RouteRecordingHint.routelessCount(rides, now: now), 1)
    }

    func testFutureDatedRideStillCounts() {
        // 时钟漂移导致的未来时间戳不该被当成「窗口外」丢掉
        XCTAssertEqual(RouteRecordingHint.routelessCount([ride(daysAgo: -1)], now: now), 1)
    }

    // MARK: - 是否提示

    func testPromptsAtThreshold() {
        XCTAssertTrue(RouteRecordingHint.shouldPrompt(
            routelessCount: 3, hasAlwaysLocation: false, dismissed: false))
    }

    func testDoesNotPromptBelowThreshold() {
        XCTAssertFalse(RouteRecordingHint.shouldPrompt(
            routelessCount: 2, hasAlwaysLocation: false, dismissed: false))
    }

    /// 已经是「始终」还催，就是纯骚扰——而且没轨迹另有原因。
    func testDoesNotPromptWhenPermissionAlreadyGranted() {
        XCTAssertFalse(RouteRecordingHint.shouldPrompt(
            routelessCount: 99, hasAlwaysLocation: true, dismissed: false))
    }

    func testDoesNotPromptOnceDismissed() {
        XCTAssertFalse(RouteRecordingHint.shouldPrompt(
            routelessCount: 99, hasAlwaysLocation: false, dismissed: true))
    }

    func testNegativeCountIsSafe() {
        XCTAssertFalse(RouteRecordingHint.shouldPrompt(
            routelessCount: -1, hasAlwaysLocation: false, dismissed: false))
    }
}
