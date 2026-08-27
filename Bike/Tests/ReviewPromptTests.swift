import XCTest
@testable import Bike

final class ReviewPromptTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)
    private func daysAgo(_ d: Double) -> Date { now.addingTimeInterval(-d * 86400) }

    /// 全门槛通过的基准参数。
    private func decide(
        installDaysAgo: Double? = 10,
        rides: Int = 8,
        lastPromptDaysAgo: Double? = nil,
        lastVersion: String? = nil,
        version: String = "1.3"
    ) -> Bool {
        ReviewPrompt.shouldPrompt(
            now: now,
            installDate: installDaysAgo.map(daysAgo),
            totalRides: rides,
            lastPromptDate: lastPromptDaysAgo.map(daysAgo),
            lastPromptedVersion: lastVersion,
            currentVersion: version
        )
    }

    func test_allGatesPass_prompts() {
        XCTAssertTrue(decide())
    }

    func test_tooFewRides_blocks() {
        XCTAssertFalse(decide(rides: 4))
        XCTAssertTrue(decide(rides: 5), "恰好 5 条命中")
    }

    func test_freshInstall_blocks() {
        XCTAssertFalse(decide(installDaysAgo: 2.5))
        XCTAssertTrue(decide(installDaysAgo: 3), "恰好 3 天命中")
        XCTAssertFalse(decide(installDaysAgo: nil), "无安装日期（刚补记）不弹")
    }

    func test_cooldown_blocks() {
        XCTAssertFalse(decide(lastPromptDaysAgo: 89, lastVersion: "1.2"))
        XCTAssertTrue(decide(lastPromptDaysAgo: 90, lastVersion: "1.2"), "恰好 90 天命中")
    }

    func test_sameVersion_blocksEvenAfterCooldown() {
        XCTAssertFalse(decide(lastPromptDaysAgo: 200, lastVersion: "1.3", version: "1.3"))
        XCTAssertTrue(decide(lastPromptDaysAgo: 200, lastVersion: "1.2", version: "1.3"))
    }

    @MainActor
    func test_registerPositiveMoment_setsInstallDateOnFirstCall() {
        let d = UserDefaults.standard
        d.removeObject(forKey: ReviewPrompt.installDateKey)
        d.removeObject(forKey: ReviewPrompt.lastPromptDateKey)
        d.removeObject(forKey: ReviewPrompt.lastPromptVersionKey)
        defer {
            d.removeObject(forKey: ReviewPrompt.installDateKey)
            d.removeObject(forKey: ReviewPrompt.lastPromptDateKey)
            d.removeObject(forKey: ReviewPrompt.lastPromptVersionKey)
        }

        XCTAssertFalse(ReviewPrompt.registerPositiveMomentAndDecide(totalRides: 99),
                       "首调补记安装日期，本次不弹")
        XCTAssertNotNil(d.object(forKey: ReviewPrompt.installDateKey))

        // 4 天后再遇价值时刻 → 弹，并记录时间与版本
        let later = Date().addingTimeInterval(4 * 86400)
        XCTAssertTrue(ReviewPrompt.registerPositiveMomentAndDecide(totalRides: 99, now: later))
        XCTAssertNotNil(d.object(forKey: ReviewPrompt.lastPromptDateKey))
        XCTAssertFalse(ReviewPrompt.registerPositiveMomentAndDecide(totalRides: 99, now: later),
                       "同版本立即再调不弹")
    }
}
