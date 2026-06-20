import Foundation
import SwiftData

/// 持久化的运动记录。领域层 `CyclingDomain.Ride` 经 `RideMapping` 映射到这里。
///
/// 注意：属性命名用 `rideID` 而非 `id`（避免与 `PersistentModel` 的 `Identifiable.id` 冲突）。
/// 新增字段都带默认值，便于 SwiftData 轻量迁移。
@Model
final class RideModel {
    @Attribute(.unique) var rideID: UUID
    /// `ActivityType.rawValue`：walking / running / cycling
    var activityTypeRaw: String = "cycling"
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
    /// 是否由被动检测自动添加（用于「待确认」指示与撤销提示）。
    var isAutoDetected: Bool = false
    var createdAt: Date

    init(
        rideID: UUID,
        activityTypeRaw: String,
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
        isAutoDetected: Bool = false,
        createdAt: Date = Date()
    ) {
        self.rideID = rideID
        self.activityTypeRaw = activityTypeRaw
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
        self.isAutoDetected = isAutoDetected
        self.createdAt = createdAt
    }

    var duration: TimeInterval { endDate.timeIntervalSince(startDate) }
}
