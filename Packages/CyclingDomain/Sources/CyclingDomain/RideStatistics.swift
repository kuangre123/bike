import Foundation

/// 单条运动的统计输入（app 层由 RideModel 投影而来，纯值语义、可单测）。
/// 距离/均速/爬升缺失时传 0；聚合时按需过滤 0。
public struct RideStat: Sendable, Equatable {
    public let date: Date
    public let distanceMeters: Double
    public let durationSeconds: Double
    public let avgSpeedMps: Double
    public let elevationGainMeters: Double
    public init(date: Date, distanceMeters: Double, durationSeconds: Double,
                avgSpeedMps: Double, elevationGainMeters: Double) {
        self.date = date
        self.distanceMeters = distanceMeters
        self.durationSeconds = durationSeconds
        self.avgSpeedMps = avgSpeedMps
        self.elevationGainMeters = elevationGainMeters
    }
}

/// 个人记录（历史最佳）。无数据时各项为 0。
public struct PersonalRecords: Sendable, Equatable {
    public var maxDistanceMeters: Double = 0
    public var maxDurationSeconds: Double = 0
    public var maxAvgSpeedMps: Double = 0
    public var maxElevationGainMeters: Double = 0
    public var mostRidesInADay: Int = 0
    public init() {}
}

/// 一段时期的汇总。
public struct PeriodTotals: Sendable, Equatable {
    public var rideCount: Int = 0
    public var distanceMeters: Double = 0
    public var durationSeconds: Double = 0
    public var elevationGainMeters: Double = 0
    public init() {}
    public init(rideCount: Int, distanceMeters: Double, durationSeconds: Double, elevationGainMeters: Double) {
        self.rideCount = rideCount
        self.distanceMeters = distanceMeters
        self.durationSeconds = durationSeconds
        self.elevationGainMeters = elevationGainMeters
    }
}

/// 按自然月的汇总桶（升序返回）。
public struct MonthBucket: Sendable, Equatable, Identifiable {
    public let year: Int
    public let month: Int
    public var totals: PeriodTotals
    public var id: String { String(format: "%04d-%02d", year, month) }
    public init(year: Int, month: Int, totals: PeriodTotals) {
        self.year = year
        self.month = month
        self.totals = totals
    }
}

/// 历史最佳记录。距离/时长/均速/爬升取各条最大；单日最多次数按自然日分组计数取最大。
public func personalRecords(_ stats: [RideStat], calendar: Calendar = .current) -> PersonalRecords {
    var r = PersonalRecords()
    guard !stats.isEmpty else { return r }
    r.maxDistanceMeters = stats.map(\.distanceMeters).max() ?? 0
    r.maxDurationSeconds = stats.map(\.durationSeconds).max() ?? 0
    r.maxAvgSpeedMps = stats.map(\.avgSpeedMps).max() ?? 0
    r.maxElevationGainMeters = stats.map(\.elevationGainMeters).max() ?? 0
    let byDay = Dictionary(grouping: stats) { calendar.startOfDay(for: $0.date) }
    r.mostRidesInADay = byDay.values.map(\.count).max() ?? 0
    return r
}

/// 全部时期的累计总量。
public func allTimeTotals(_ stats: [RideStat]) -> PeriodTotals {
    stats.reduce(into: PeriodTotals()) { acc, s in
        acc.rideCount += 1
        acc.distanceMeters += s.distanceMeters
        acc.durationSeconds += s.durationSeconds
        acc.elevationGainMeters += s.elevationGainMeters
    }
}

/// 指定起点之后（含）的时期汇总，用于「本周/本月」。
public func totals(_ stats: [RideStat], since cutoff: Date) -> PeriodTotals {
    allTimeTotals(stats.filter { $0.date >= cutoff })
}

/// 按自然月分桶汇总，升序（旧→新）。
public func monthlyTotals(_ stats: [RideStat], calendar: Calendar = .current) -> [MonthBucket] {
    let grouped = Dictionary(grouping: stats) { s -> DateComponents in
        calendar.dateComponents([.year, .month], from: s.date)
    }
    return grouped
        .map { comps, group in
            MonthBucket(year: comps.year ?? 0, month: comps.month ?? 0, totals: allTimeTotals(group))
        }
        .sorted { ($0.year, $0.month) < ($1.year, $1.month) }
}

/// 当前连续骑行天数：从今天往回数连续有骑行的自然日。
/// 宽限一天——今天还没骑但昨天骑了，连续仍成立（从昨天起算）；最近骑行日早于昨天则为 0。
public func currentStreakDays(rideDates: [Date], today: Date, calendar: Calendar = .current) -> Int {
    let days = Set(rideDates.map { calendar.startOfDay(for: $0) })
    guard !days.isEmpty else { return 0 }
    let start = calendar.startOfDay(for: today)
    guard let yesterday = calendar.date(byAdding: .day, value: -1, to: start) else { return 0 }

    // 锚点：今天有骑从今天起，否则昨天有骑从昨天起，否则连续中断为 0。
    var cursor: Date
    if days.contains(start) { cursor = start }
    else if days.contains(yesterday) { cursor = yesterday }
    else { return 0 }

    var count = 0
    while days.contains(cursor) {
        count += 1
        guard let prev = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
        cursor = prev
    }
    return count
}

/// 历史最长连续骑行天数。
public func longestStreakDays(rideDates: [Date], calendar: Calendar = .current) -> Int {
    let days = rideDates.map { calendar.startOfDay(for: $0) }
    let unique = Set(days).sorted()
    guard !unique.isEmpty else { return 0 }
    var longest = 1, run = 1
    for i in 1..<max(1, unique.count) {
        let gap = calendar.dateComponents([.day], from: unique[i - 1], to: unique[i]).day ?? 0
        if gap == 1 { run += 1 } else { run = 1 }
        longest = max(longest, run)
    }
    return unique.count == 1 ? 1 : longest
}
