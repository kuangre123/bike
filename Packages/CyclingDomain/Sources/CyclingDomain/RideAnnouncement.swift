import Foundation

/// 一次语音播报的内容。
///
/// 距离和均速可能是 nil —— GPS 没动、没拿到定位时就是没有，
/// 播报时跳过这两项，不念「0.0 公里，平均时速 0」冒充有数据。
public struct RideAnnouncement: Equatable, Sendable {
    public let durationSeconds: TimeInterval
    public let distanceMeters: Double?
    public let avgSpeedMps: Double?

    public init(durationSeconds: TimeInterval, distanceMeters: Double?, avgSpeedMps: Double?) {
        self.durationSeconds = durationSeconds
        self.distanceMeters = distanceMeters
        self.avgSpeedMps = avgSpeedMps
    }
}

/// 里程碑式播报的触发判断：每满 N 分钟、每满 M 公里播一次。
///
/// 只管「该不该播」，不管播什么声音——朗读是 app 层的事，这里是纯逻辑，可单测。
public struct AnnouncementTracker: Equatable, Sendable {
    public static let defaultDurationIntervalMinutes = 10
    public static let defaultDistanceIntervalKilometers: Double = 5

    private let durationIntervalMinutes: Int
    private let distanceIntervalKilometers: Double
    /// 已播报到第几个里程碑（不是次数，是刻度）。
    private var lastDurationMilestone = 0
    private var lastDistanceMilestone = 0

    public init(
        durationIntervalMinutes: Int = defaultDurationIntervalMinutes,
        distanceIntervalKilometers: Double = defaultDistanceIntervalKilometers
    ) {
        self.durationIntervalMinutes = durationIntervalMinutes
        self.distanceIntervalKilometers = distanceIntervalKilometers
    }

    /// 喂进当前进度，返回这一刻该播的内容；没到新里程碑就是 nil。
    ///
    /// - 时长用**有效时长**（暂停不计），所以停着等红灯不会一直播。
    /// - 跨过多个里程碑（比如切后台回来已经 35 分钟）只播一次，不补播中间的。
    /// - 时长和距离同时越线也只播一次——内容本来就包含全部数据。
    public mutating func advance(
        durationSeconds: TimeInterval,
        distanceMeters: Double?
    ) -> RideAnnouncement? {
        // 负距离只可能来自坏数据，按「没有」处理。
        let distance = (distanceMeters ?? -1) >= 0 ? distanceMeters : nil

        let durationMilestone = milestone(
            value: durationSeconds / 60, interval: Double(durationIntervalMinutes))
        let distanceMilestone = distance.map {
            milestone(value: $0 / 1000, interval: distanceIntervalKilometers)
        } ?? 0

        let durationAdvanced = durationMilestone > lastDurationMilestone
        let distanceAdvanced = distanceMilestone > lastDistanceMilestone
        guard durationAdvanced || distanceAdvanced else { return nil }

        // 两个刻度都推到当前位置：否则下一次 tick 会因为另一个也「涨过」而再播一遍。
        lastDurationMilestone = durationMilestone
        lastDistanceMilestone = distanceMilestone

        return RideAnnouncement(
            durationSeconds: durationSeconds,
            distanceMeters: distance,
            avgSpeedMps: averageSpeed(distanceMeters: distance, durationSeconds: durationSeconds)
        )
    }

    /// 当前落在第几个刻度上。间隔 <= 0 时恒为 0，等于关掉这一路触发（不除零、也不每次都播）。
    private func milestone(value: Double, interval: Double) -> Int {
        guard interval > 0, value >= 0 else { return 0 }
        return Int(value / interval)
    }

    /// 均速。没有距离、或时长为 0 时是 nil —— 不拿轨迹或时长去凑一个数。
    private func averageSpeed(distanceMeters: Double?, durationSeconds: TimeInterval) -> Double? {
        guard let distanceMeters, durationSeconds > 0 else { return nil }
        return distanceMeters / durationSeconds
    }
}
