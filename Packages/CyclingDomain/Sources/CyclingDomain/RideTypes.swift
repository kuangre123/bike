import Foundation

/// 一次骑行记录的数据来源。
public enum RideSource: String, Sendable, Codable {
    case motionOnly   // 仅 CoreMotion 运动历史（有时长，无路线）
    case gpsTracked   // 仅 GPS 实采（理论边缘情况）
    case merged       // 运动历史 + GPS 实采都覆盖（最完整）
}

/// CoreMotion 回溯查询得到的一个骑行时段（基线层输入）。
public struct MotionSegment: Equatable, Sendable {
    public let start: Date
    public let end: Date
    /// CoreMotion 置信度：0=low, 1=medium, 2=high
    public let confidence: Int
    public init(start: Date, end: Date, confidence: Int) {
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

/// LiveRideTracker 实采到的一次骑行（增强层输出，进对账器）。
public struct TrackedRide: Equatable, Sendable {
    public let start: Date
    public let end: Date
    public let samples: [GPSSample]
    public init(start: Date, end: Date, samples: [GPSSample]) {
        self.start = start
        self.end = end
        self.samples = samples
    }
}

/// 对账后的最终骑行记录（领域层输出；M2 会映射成 SwiftData @Model）。
public struct Ride: Equatable, Sendable {
    public let start: Date
    public let end: Date
    public let source: RideSource
    public let distanceMeters: Double?
    public let avgSpeedMps: Double?
    public let calories: Double?
    public let confidence: Int
    public init(start: Date, end: Date, source: RideSource,
                distanceMeters: Double?, avgSpeedMps: Double?,
                calories: Double?, confidence: Int) {
        self.start = start
        self.end = end
        self.source = source
        self.distanceMeters = distanceMeters
        self.avgSpeedMps = avgSpeedMps
        self.calories = calories
        self.confidence = confidence
    }
    public var duration: TimeInterval { end.timeIntervalSince(start) }
}
