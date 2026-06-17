import Foundation
import SwiftData

/// 持久化的骑行记录。领域层 `CyclingDomain.Ride` 经 `RideMapping` 映射到这里。
///
/// 注意：属性命名用 `rideID` 而非 `id` —— SwiftData 的 `PersistentModel` 已通过
/// `Identifiable` 提供 `id`（= PersistentIdentifier），自定义 `id` 属性会冲突。
@Model
final class RideModel {
    @Attribute(.unique) var rideID: UUID
    var startDate: Date
    var endDate: Date
    /// `RideSource.rawValue`
    var sourceRaw: String
    var distanceMeters: Double?
    var avgSpeedMps: Double?
    var calories: Double?
    var confidence: Int
    /// JSON 编码的 `[RoutePointDTO]`；无 GPS 时为 nil。
    var routeData: Data?
    var avgHeartRate: Double?
    var healthKitWorkoutUUID: UUID?
    var createdAt: Date

    init(
        rideID: UUID,
        startDate: Date,
        endDate: Date,
        sourceRaw: String,
        distanceMeters: Double?,
        avgSpeedMps: Double?,
        calories: Double?,
        confidence: Int,
        routeData: Data? = nil,
        avgHeartRate: Double? = nil,
        healthKitWorkoutUUID: UUID? = nil,
        createdAt: Date = Date()
    ) {
        self.rideID = rideID
        self.startDate = startDate
        self.endDate = endDate
        self.sourceRaw = sourceRaw
        self.distanceMeters = distanceMeters
        self.avgSpeedMps = avgSpeedMps
        self.calories = calories
        self.confidence = confidence
        self.routeData = routeData
        self.avgHeartRate = avgHeartRate
        self.healthKitWorkoutUUID = healthKitWorkoutUUID
        self.createdAt = createdAt
    }

    var duration: TimeInterval { endDate.timeIntervalSince(startDate) }
}
