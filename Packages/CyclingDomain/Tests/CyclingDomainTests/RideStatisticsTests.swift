import XCTest
@testable import CyclingDomain

final class RideStatisticsTests: XCTestCase {
    private var cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        return c
    }()

    private func day(_ s: String) -> Date {
        let f = DateFormatter()
        f.calendar = cal
        f.timeZone = cal.timeZone
        f.dateFormat = "yyyy-MM-dd HH:mm"
        return f.date(from: s)!
    }

    private func stat(_ date: String, dist: Double = 0, dur: Double = 0,
                      spd: Double = 0, elev: Double = 0) -> RideStat {
        RideStat(date: day(date), distanceMeters: dist, durationSeconds: dur,
                 avgSpeedMps: spd, elevationGainMeters: elev)
    }

    // MARK: personalRecords

    func test_personalRecords_takesMaxima() {
        let stats = [
            stat("2026-08-01 08:00", dist: 5000, dur: 1200, spd: 5, elev: 40),
            stat("2026-08-01 18:00", dist: 8000, dur: 900, spd: 8, elev: 10),
            stat("2026-08-03 09:00", dist: 3000, dur: 2000, spd: 4, elev: 120),
        ]
        let r = personalRecords(stats, calendar: cal)
        XCTAssertEqual(r.maxDistanceMeters, 8000, accuracy: 0.001)
        XCTAssertEqual(r.maxDurationSeconds, 2000, accuracy: 0.001)
        XCTAssertEqual(r.maxAvgSpeedMps, 8, accuracy: 0.001)
        XCTAssertEqual(r.maxElevationGainMeters, 120, accuracy: 0.001)
        XCTAssertEqual(r.mostRidesInADay, 2) // 8-01 有两条
    }

    func test_personalRecords_emptyIsZero() {
        let r = personalRecords([], calendar: cal)
        XCTAssertEqual(r, PersonalRecords())
    }

    // MARK: totals

    func test_allTimeTotals_sums() {
        let stats = [
            stat("2026-08-01 08:00", dist: 5000, dur: 1200, elev: 40),
            stat("2026-08-03 09:00", dist: 3000, dur: 2000, elev: 120),
        ]
        let t = allTimeTotals(stats)
        XCTAssertEqual(t.rideCount, 2)
        XCTAssertEqual(t.distanceMeters, 8000, accuracy: 0.001)
        XCTAssertEqual(t.durationSeconds, 3200, accuracy: 0.001)
        XCTAssertEqual(t.elevationGainMeters, 160, accuracy: 0.001)
    }

    func test_totalsSince_filters() {
        let stats = [
            stat("2026-08-01 08:00", dist: 5000),
            stat("2026-08-10 09:00", dist: 3000),
        ]
        let t = totals(stats, since: day("2026-08-05 00:00"))
        XCTAssertEqual(t.rideCount, 1)
        XCTAssertEqual(t.distanceMeters, 3000, accuracy: 0.001)
    }

    // MARK: monthlyTotals

    func test_monthlyTotals_bucketsAndSorts() {
        let stats = [
            stat("2026-07-20 08:00", dist: 1000),
            stat("2026-08-01 08:00", dist: 2000),
            stat("2026-08-15 08:00", dist: 3000),
        ]
        let months = monthlyTotals(stats, calendar: cal)
        XCTAssertEqual(months.count, 2)
        XCTAssertEqual(months[0].year, 2026); XCTAssertEqual(months[0].month, 7)
        XCTAssertEqual(months[0].totals.distanceMeters, 1000, accuracy: 0.001)
        XCTAssertEqual(months[1].month, 8)
        XCTAssertEqual(months[1].totals.rideCount, 2)
        XCTAssertEqual(months[1].totals.distanceMeters, 5000, accuracy: 0.001)
    }

    // MARK: streaks

    func test_currentStreak_countsBackFromToday() {
        let dates = [day("2026-08-24 08:00"), day("2026-08-25 20:00"), day("2026-08-26 07:00")]
        let n = currentStreakDays(rideDates: dates, today: day("2026-08-26 12:00"), calendar: cal)
        XCTAssertEqual(n, 3)
    }

    func test_currentStreak_graceForYesterday() {
        // 今天还没骑，但昨天+前天骑了 → 连续从昨天起算 = 2
        let dates = [day("2026-08-24 08:00"), day("2026-08-25 20:00")]
        let n = currentStreakDays(rideDates: dates, today: day("2026-08-26 12:00"), calendar: cal)
        XCTAssertEqual(n, 2)
    }

    func test_currentStreak_brokenIsZero() {
        // 最近骑行是前天，今天昨天都没骑 → 中断
        let dates = [day("2026-08-24 08:00")]
        let n = currentStreakDays(rideDates: dates, today: day("2026-08-26 12:00"), calendar: cal)
        XCTAssertEqual(n, 0)
    }

    func test_currentStreak_multipleRidesSameDayCountOnce() {
        let dates = [day("2026-08-26 07:00"), day("2026-08-26 19:00"), day("2026-08-25 08:00")]
        let n = currentStreakDays(rideDates: dates, today: day("2026-08-26 12:00"), calendar: cal)
        XCTAssertEqual(n, 2)
    }

    func test_longestStreak_findsMaxRun() {
        // 连续 8-01,02,03（3）；断；8-10,11（2）→ 最长 3
        let dates = ["2026-08-01", "2026-08-02", "2026-08-03", "2026-08-10", "2026-08-11"]
            .map { day("\($0) 08:00") }
        XCTAssertEqual(longestStreakDays(rideDates: dates, calendar: cal), 3)
    }

    func test_longestStreak_singleDayIsOne() {
        XCTAssertEqual(longestStreakDays(rideDates: [day("2026-08-01 08:00")], calendar: cal), 1)
    }

    func test_longestStreak_emptyIsZero() {
        XCTAssertEqual(longestStreakDays(rideDates: [], calendar: cal), 0)
    }
}
