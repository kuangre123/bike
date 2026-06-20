import Foundation
import CyclingDomain

/// 领域 `Ride` <-> 持久化 `RideModel` 的映射。纯函数，可单测。
enum RideMapping {
    /// 由领域 Ride 造一个新的持久化模型（每次生成新 rideID）。
    static func makeModel(from ride: Ride, autoDetected: Bool = false) -> RideModel {
        RideModel(
            rideID: UUID(),
            activityTypeRaw: ride.activityType.rawValue,
            startDate: ride.start,
            endDate: ride.end,
            sourceRaw: ride.source.rawValue,
            distanceMeters: ride.distanceMeters,
            avgSpeedMps: ride.avgSpeedMps,
            calories: ride.calories,
            confidence: ride.confidence,
            avgHeartRate: ride.avgHeartRate,
            isAutoDetected: autoDetected
        )
    }

    static func source(of model: RideModel) -> RideSource {
        RideSource(rawValue: model.sourceRaw) ?? .motionOnly
    }

    static func activityType(of model: RideModel) -> ActivityType {
        ActivityType(rawValue: model.activityTypeRaw) ?? .cycling
    }
}
