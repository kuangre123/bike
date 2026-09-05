import Foundation
import SwiftData
import CyclingDomain

/// 保存结果：实际插入的模型 + 被替换旧记录已写入健康的 workout UUID（调用方负责从 Apple 健康删除）。
struct RideSaveResult {
    let inserted: [RideModel]
    let replacedHealthWorkoutUUIDs: [UUID]

    /// 计算属性而非 `static let`：`RideModel` 非 Sendable，全局存储在 Swift 6 下不安全。
    static var empty: RideSaveResult { RideSaveResult(inserted: [], replacedHealthWorkoutUUIDs: []) }
}

/// 包装 `ModelContext`：保存对账后的运动（按时间去重）、查询。
/// 普通 struct（非 @MainActor）—— 只在主线程（UI / 检测管线 hop 后）同步调用。
struct RideStore {
    let context: ModelContext

    /// 手动记录视为「同一时段冲突」的最小重叠秒数；小于它的边界擦碰保留共存。
    private static let conflictOverlapSeconds: TimeInterval = 60

    init(context: ModelContext) {
        self.context = context
    }

    /// 保存一批领域 Ride，按时间重叠去重：
    /// - 自动检测（autoDetected=true）：与任何已有记录重叠即冲突；只在明显更完整时
    ///   替换同类型的旧自动记录，绝不覆盖手动记录。
    /// - 手动记录（autoDetected=false）：用户实录是该时段的事实来源——替换与之大幅
    ///   重叠（≥60 秒）的自动记录（如骑行途中被动检测先存的估算记录）；轻微边界重叠
    ///   共存；与已有手动记录大幅重叠仍阻止。
    @discardableResult
    func save(_ rides: [Ride], autoDetected: Bool) throws -> RideSaveResult {
        var existing = try context.fetch(FetchDescriptor<RideModel>())
        var inserted: [RideModel] = []
        var replacedHealthUUIDs: [UUID] = []
        for ride in rides where ride.duration >= RideDetectionPolicy.minimumRideDuration {
            let overlapping = existing.filter { overlapSeconds(of: $0, with: ride) > 0 }
            let conflicting = autoDetected
                ? overlapping
                : overlapping.filter { overlapSeconds(of: $0, with: ride) >= Self.conflictOverlapSeconds }
            if !conflicting.isEmpty {
                let replaceable = conflicting.filter { model in
                    if autoDetected {
                        return model.isAutoDetected
                            && model.activityTypeRaw == ride.activityType.rawValue
                            && isBetterAutoDetectedRide(ride, than: model)
                    }
                    return model.isAutoDetected
                }
                let blocked = conflicting.count != replaceable.count
                if blocked { continue }
                for model in replaceable {
                    if let uuid = model.healthKitWorkoutUUID {
                        replacedHealthUUIDs.append(uuid)
                    }
                    context.delete(model)
                    existing.removeAll { $0.rideID == model.rideID }
                }
            }
            let model = RideMapping.makeModel(from: ride, autoDetected: autoDetected)
            context.insert(model)
            existing.append(model)
            inserted.append(model)
        }
        try context.save()
        return RideSaveResult(inserted: inserted, replacedHealthWorkoutUUIDs: replacedHealthUUIDs)
    }

    private func overlapSeconds(of model: RideModel, with ride: Ride) -> TimeInterval {
        max(0, min(model.endDate, ride.end).timeIntervalSince(max(model.startDate, ride.start)))
    }

    /// 只在自动检测结果明显更完整时替换旧记录，避免每次对账把同一段运动反复写进 Apple 健康。
    private func isBetterAutoDetectedRide(_ ride: Ride, than model: RideModel) -> Bool {
        if (model.routeData == nil || model.routeData?.isEmpty == true), ride.route?.isEmpty == false {
            return true
        }
        if model.distanceMeters == nil, ride.distanceMeters != nil {
            return true
        }
        return ride.duration >= model.duration + 60
    }

    /// 全部运动，按开始时间倒序。
    func allRides() throws -> [RideModel] {
        try context.fetch(
            FetchDescriptor<RideModel>(sortBy: [SortDescriptor(\.startDate, order: .reverse)])
        )
    }
}
