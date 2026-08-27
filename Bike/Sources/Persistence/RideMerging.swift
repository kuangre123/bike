import Foundation
import SwiftData
import CyclingDomain

/// 把两条相邻记录合并成一条（解决被动检测偶尔把一次骑行拆成两段）。
/// 纯字段合并（`apply`）与健康联动（`merge`）分离，前者可单测。
enum RideMerging {
    /// 允许合并的最大间隔（后一条开始 - 前一条结束）。
    static let maxGapSeconds: TimeInterval = 2 * 3600

    /// 同类型、都未排除、时间间隔 ≤ 2 小时才可合并。
    static func canMerge(_ a: RideModel, _ b: RideModel) -> Bool {
        guard a.activityTypeRaw == b.activityTypeRaw,
              !a.excludedAsEBike, !b.excludedAsEBike else { return false }
        let earlier = a.startDate <= b.startDate ? a : b
        let later = earlier === a ? b : a
        return later.startDate.timeIntervalSince(earlier.endDate) <= maxGapSeconds
    }

    /// 把 `absorbed` 的数据并入 `survivor`（不动数据库、不动健康）。
    /// 时长取两段有效时长之和（间隙不计入）；距离/卡路里求和；心率按时长加权；轨迹按时间拼接。
    static func apply(absorbing absorbed: RideModel, into survivor: RideModel) {
        // 先取值再赋值，避免读到已被改写的字段
        let durA = survivor.duration, durB = absorbed.duration
        let totalDuration = durA + durB

        let distances = [survivor.distanceMeters, absorbed.distanceMeters].compactMap { $0 }
        let totalDistance = distances.isEmpty ? nil : distances.reduce(0, +)

        let calories = [survivor.calories, absorbed.calories].compactMap { $0 }
        let totalCalories = calories.isEmpty ? nil : calories.reduce(0, +)

        let hrWeighted: Double? = {
            var weighted = 0.0, weight = 0.0
            if let hr = survivor.avgHeartRate { weighted += hr * durA; weight += durA }
            if let hr = absorbed.avgHeartRate { weighted += hr * durB; weight += durB }
            return weight > 0 ? weighted / weight : nil
        }()

        let mergedRoute = (RideMapping.decodeRoute(survivor.routeData) + RideMapping.decodeRoute(absorbed.routeData))
            .sorted { $0.timestamp < $1.timestamp }

        survivor.startDate = min(survivor.startDate, absorbed.startDate)
        survivor.endDate = max(survivor.endDate, absorbed.endDate)
        survivor.activeDurationSeconds = totalDuration
        survivor.distanceMeters = totalDistance
        survivor.avgSpeedMps = (totalDistance != nil && totalDuration > 0) ? totalDistance! / totalDuration : nil
        survivor.calories = totalCalories
        survivor.avgHeartRate = hrWeighted
        survivor.routeData = mergedRoute.isEmpty ? nil : try? JSONEncoder().encode(mergedRoute)
        survivor.confidence = min(survivor.confidence, absorbed.confidence)
        if survivor.sourceRaw != absorbed.sourceRaw {
            survivor.sourceRaw = RideSource.merged.rawValue
        }
        survivor.isAutoDetected = false   // 用户手动整理过
    }

    /// 合并并落库：早的一条为幸存者；删除晚的一条；
    /// 若任一条写过 Apple 健康 → 删旧 workout，按「自动写回」开关重写合并后的 workout。
    @MainActor
    static func merge(_ a: RideModel, _ b: RideModel, context: ModelContext) async {
        guard canMerge(a, b) else { return }
        let survivor = a.startDate <= b.startDate ? a : b
        let absorbed = survivor === a ? b : a
        let oldUUIDs = [survivor.healthKitWorkoutUUID, absorbed.healthKitWorkoutUUID].compactMap { $0 }

        apply(absorbing: absorbed, into: survivor)
        survivor.healthKitWorkoutUUID = nil
        context.delete(absorbed)
        try? context.save()

        guard !oldUUIDs.isEmpty else { return }
        let health = HealthService()
        guard await health.requestWriteAuthorization() else { return }
        for uuid in oldUUIDs { _ = await health.deleteWorkout(uuid: uuid) }

        let writeBack = UserDefaults.standard.object(forKey: "healthWriteBack") as? Bool ?? true
        guard writeBack else { return }
        if let uuid = await health.saveWorkout(
            activityType: RideMapping.activityType(of: survivor),
            start: survivor.startDate,
            end: survivor.startDate.addingTimeInterval(survivor.duration),
            calories: survivor.calories,
            distanceMeters: survivor.distanceMeters,
            avgSpeedMps: survivor.avgSpeedMps,
            route: RideMapping.decodeRoute(survivor.routeData)
        ) {
            survivor.healthKitWorkoutUUID = uuid
            try? context.save()
        }
    }
}
