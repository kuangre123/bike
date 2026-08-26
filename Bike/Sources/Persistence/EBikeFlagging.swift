import Foundation
import SwiftData
import CyclingDomain

/// 「疑似电动车」派生判定 + 排除/恢复语义（含 Apple 健康联动）。
///
/// 判定是软提示：由存储的轨迹逐点速度实时计算（`isSuspectedEBike`），不落库；
/// 只持久化用户的排除决定（`RideModel.excludedAsEBike`）。
enum EBikeFlagging {
    /// 设置开关「自动标注疑似电动车」（默认开）。
    /// 只控制徽标显示；已排除状态不受影响。
    static var autoFlagEnabled: Bool {
        UserDefaults.standard.object(forKey: "ebikeAutoFlag") as? Bool ?? true
    }

    /// 该记录是否命中「疑似电动车」启发式（派生量，随调随算）。
    static func isSuspected(_ ride: RideModel) -> Bool {
        isSuspectedEBike(
            activityType: RideMapping.activityType(of: ride),
            durationSeconds: ride.duration,
            speedSamplesMps: RideMapping.decodeRoute(ride.routeData).map(\.speedMps)
        )
    }

    /// 时间线行是否显示「疑似电动车」徽标。
    static func showsBadge(for ride: RideModel) -> Bool {
        autoFlagEnabled && !ride.excludedAsEBike && isSuspected(ride)
    }

    /// 排除：置标记（本地立即生效）；若已写入 Apple 健康则从健康删除。
    /// 保留 `healthKitWorkoutUUID` 作为「曾写过健康」的凭据，供恢复时判断是否重写。
    @MainActor
    static func exclude(_ ride: RideModel, context: ModelContext) async {
        ride.excludedAsEBike = true
        try? context.save()

        if let uuid = ride.healthKitWorkoutUUID {
            let health = HealthService()
            _ = await health.requestWriteAuthorization()
            _ = await health.deleteWorkout(uuid: uuid)
        }
    }

    /// 恢复：清标记；若排除前写过健康且「自动写回」开启，重写 workout 并回填新 UUID。
    /// `saveWorkout` 幂等，重复恢复安全。
    @MainActor
    static func restore(_ ride: RideModel, context: ModelContext) async {
        ride.excludedAsEBike = false
        try? context.save()

        let writeBack = UserDefaults.standard.object(forKey: "healthWriteBack") as? Bool ?? true
        guard writeBack, ride.healthKitWorkoutUUID != nil else { return }

        let health = HealthService()
        guard await health.requestWriteAuthorization() else { return }
        if let uuid = await health.saveWorkout(
            activityType: RideMapping.activityType(of: ride),
            start: ride.startDate,
            end: ride.startDate.addingTimeInterval(ride.duration),
            calories: ride.calories,
            distanceMeters: ride.distanceMeters,
            avgSpeedMps: ride.avgSpeedMps,
            route: RideMapping.decodeRoute(ride.routeData)
        ) {
            ride.healthKitWorkoutUUID = uuid
            try? context.save()
        }
    }
}
