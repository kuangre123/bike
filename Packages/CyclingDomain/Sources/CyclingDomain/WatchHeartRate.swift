import Foundation

/// 手表 → 手机同步的一次心率读数（经 WatchConnectivity 传输）。
public struct WatchHeartRate: Codable, Sendable, Equatable {
    public let bpm: Double
    /// 心率的**测量**时间，不是发送时间。手表不在运动中时几分钟才被动测一次，
    /// 若按发送时间算新鲜度，会把几分钟前的旧值当成实时心率显示。
    public let measuredAt: Date

    public init(bpm: Double, measuredAt: Date) {
        self.bpm = bpm
        self.measuredAt = measuredAt
    }
}

/// 读数的新鲜度。手表在运动会话中每几秒测一次，平时几分钟才测一次，
/// 所以「有点旧」是常态——如实标成「最近心率」，不冒充实时值。
public enum WatchHeartRateFreshness: Sendable, Equatable {
    case live
    case recent
    /// 太旧，跟当前状态已经没关系，不该再显示。
    case stale
}

extension WatchHeartRate {
    /// 20 秒内算实时（运动会话里的采样间隔约 5 秒）。
    public static let liveWindow: TimeInterval = 20
    /// 超过 15 分钟就不再显示。
    public static let recentWindow: TimeInterval = 15 * 60

    public func freshness(at date: Date) -> WatchHeartRateFreshness {
        // 手表时钟可能比手机略快，未来时间戳按实时处理，不当成异常。
        let age = date.timeIntervalSince(measuredAt)
        if age < Self.liveWindow { return .live }
        if age <= Self.recentWindow { return .recent }
        return .stale
    }

    /// 取测量时间更新的一条。
    ///
    /// 手机上同时有两个心率来源：手表实时推来的读数，和手表回写进 Apple 健康后
    /// 手机轮询到的样本。后者要等系统后台同步，通常慢几十秒到几分钟，
    /// 所以不能按「谁后到用谁」，只能按测量时间比。
    public static func fresher(_ lhs: WatchHeartRate?, _ rhs: WatchHeartRate?) -> WatchHeartRate? {
        switch (lhs, rhs) {
        case let (l?, r?): return l.measuredAt >= r.measuredAt ? l : r
        case let (l?, nil): return l
        case let (nil, r?): return r
        case (nil, nil): return nil
        }
    }
}
