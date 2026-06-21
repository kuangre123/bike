import Foundation

/// 手机 → 手表同步的「今日概览」（经 WatchConnectivity applicationContext 传输）。
public struct WatchDaySummary: Codable, Sendable, Equatable {
    public let count: Int
    public let durationSeconds: TimeInterval
    public let distanceMeters: Double
    public init(count: Int, durationSeconds: TimeInterval, distanceMeters: Double) {
        self.count = count
        self.durationSeconds = durationSeconds
        self.distanceMeters = distanceMeters
    }
}
