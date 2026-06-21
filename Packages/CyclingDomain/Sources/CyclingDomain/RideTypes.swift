import Foundation

/// 一次运动记录的数据来源。
public enum RideSource: String, Sendable, Codable {
    case motionOnly     // 仅 CoreMotion 运动历史（有时长，无路线）
    case gpsTracked     // 仅 GPS 实采
    case merged         // 运动历史 + GPS 实采都覆盖（最完整）
    case heartRateOnly  // 仅心率检测（无动作分类、无 GPS）—— 心率兜底
}

/// CoreMotion 回溯查询得到的一个运动时段（基线层输入）。
public struct MotionSegment: Equatable, Sendable {
    public let activityType: ActivityType
    public let start: Date
    public let end: Date
    /// CoreMotion 置信度：0=low, 1=medium, 2=high
    public let confidence: Int
    public init(activityType: ActivityType, start: Date, end: Date, confidence: Int) {
        self.activityType = activityType
        self.start = start
        self.end = end
        self.confidence = confidence
    }
    public var duration: TimeInterval { end.timeIntervalSince(start) }
}

/// 一个 GPS 采样点（增强层输入）。经纬度用普通 Double，保持包无 CoreLocation 依赖。
public struct GPSSample: Equatable, Sendable {
    public let timestamp: Date
    public let latitude: Double
    public let longitude: Double
    /// 瞬时速度 m/s，负值表示无效。
    public let speedMps: Double
    public init(timestamp: Date, latitude: Double, longitude: Double, speedMps: Double) {
        self.timestamp = timestamp
        self.latitude = latitude
        self.longitude = longitude
        self.speedMps = speedMps
    }
}

/// LiveRideTracker 实采到的一次运动（增强层输出，进对账器）。
public struct TrackedRide: Equatable, Sendable {
    public let activityType: ActivityType
    public let start: Date
    public let end: Date
    public let samples: [GPSSample]
    public init(activityType: ActivityType, start: Date, end: Date, samples: [GPSSample]) {
        self.activityType = activityType
        self.start = start
        self.end = end
        self.samples = samples
    }
}

/// 对账后的最终运动记录（领域层输出；app 层会映射成 SwiftData 模型）。
/// 注：类型名暂沿用 `Ride`（历史原因），实际承载任意 `ActivityType`，后续可统一改名 Workout。
public struct Ride: Equatable, Sendable {
    public let activityType: ActivityType
    public let start: Date
    public let end: Date
    public let source: RideSource
    public let distanceMeters: Double?
    public let avgSpeedMps: Double?
    public let calories: Double?
    public let confidence: Int
    /// 均心率（bpm），来自 HealthKit；无则 nil。
    public let avgHeartRate: Double?
    /// 有效运动时长（秒）。手动暂停时会小于起止时间差；自动检测记录通常为 nil。
    public let activeDuration: TimeInterval?
    /// GPS 轨迹点（有实采时）；用于地图展示与写回 HealthKit 路线。
    public let route: [GPSSample]?
    public init(activityType: ActivityType, start: Date, end: Date, source: RideSource,
                distanceMeters: Double?, avgSpeedMps: Double?,
                calories: Double?, confidence: Int, avgHeartRate: Double? = nil,
                activeDuration: TimeInterval? = nil, route: [GPSSample]? = nil) {
        self.activityType = activityType
        self.start = start
        self.end = end
        self.source = source
        self.distanceMeters = distanceMeters
        self.avgSpeedMps = avgSpeedMps
        self.calories = calories
        self.confidence = confidence
        self.avgHeartRate = avgHeartRate
        self.activeDuration = activeDuration
        self.route = route
    }
    public var duration: TimeInterval { activeDuration ?? end.timeIntervalSince(start) }

    /// 返回一个附加/替换均心率的副本（保留其余字段，含路线）。
    public func withAvgHeartRate(_ bpm: Double?) -> Ride {
        Ride(activityType: activityType, start: start, end: end, source: source,
             distanceMeters: distanceMeters, avgSpeedMps: avgSpeedMps, calories: calories,
             confidence: confidence, avgHeartRate: bpm, activeDuration: activeDuration, route: route)
    }
}
