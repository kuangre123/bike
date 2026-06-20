import Foundation

/// 被动可检测的运动类型 —— iPhone 上 CoreMotion 能分类的 ambulatory 活动。
/// （健身房/游泳/瑜伽等无位移特征的运动 iPhone 测不到，需 Apple Watch，留待后续。）
public enum ActivityType: String, Sendable, Codable, CaseIterable {
    case walking
    case running
    case cycling
    /// 心率检测到、但 iPhone 动作分类不出类型的运动（器械 / 健身房等）。需 Apple Watch 心率。
    case other
}
