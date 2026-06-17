import Foundation
import CyclingDomain

/// 领域 `Ride` <-> 持久化 `RideModel` 的映射。纯函数，可单测。
enum RideMapping {
    /// 由领域 Ride 造一个新的持久化模型（每次生成新 rideID）。
    static func makeModel(from ride: Ride) -> RideModel {
        RideModel(
            rideID: UUID(),
            startDate: ride.start,
            endDate: ride.end,
            sourceRaw: ride.source.rawValue,
            distanceMeters: ride.distanceMeters,
            avgSpeedMps: ride.avgSpeedMps,
            calories: ride.calories,
            confidence: ride.confidence
        )
    }

    /// 读出持久化模型的来源枚举（解析失败兜底为 motionOnly）。
    static func source(of model: RideModel) -> RideSource {
        RideSource(rawValue: model.sourceRaw) ?? .motionOnly
    }
}
