import Foundation
import SwiftData
import CyclingDomain

/// 一条记录的来路，决定它和已有记录冲突时谁让谁。
///
/// 强弱：`manual` > `externalImport` > `autoDetected`。理由是「谁的数据更接近事实」——
/// 用户在本 app 里实录 > 第三方设备实测 > 本 app 从动作历史估算。
enum RideProvenance {
    /// 被动检测的估算记录。
    case autoDetected
    /// 从 Apple 健康导入的第三方设备 / app 记录。
    case externalImport
    /// 用户在本 app 里手动实录。
    case manual

    var isAutoDetected: Bool { self == .autoDetected }
}

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

    /// 视为「同一时段冲突」的最小重叠秒数；小于它的边界擦碰保留共存。
    /// 只对 `manual` / `externalImport` 生效；自动检测任何重叠都算冲突。
    private static let conflictOverlapSeconds: TimeInterval = 60

    /// 待插入的一条：领域 Ride + 外部来源信息（本地记录时为 nil）。
    private struct PendingRide {
        let ride: Ride
        var externalWorkoutUUID: UUID?
        var externalSourceName: String?
    }

    init(context: ModelContext) {
        self.context = context
    }

    /// 保存一批领域 Ride，按时间重叠去重。规则见 `RideProvenance`。
    @discardableResult
    func save(_ rides: [Ride], provenance: RideProvenance) throws -> RideSaveResult {
        try insert(rides.map { PendingRide(ride: $0) }, provenance: provenance)
    }

    /// 保存一批从 Apple 健康导入的第三方运动，并记下它们的来源，防止下次重复导入。
    @discardableResult
    func saveImported(_ workouts: [ExternalWorkout]) throws -> RideSaveResult {
        try insert(
            workouts.map {
                PendingRide(
                    ride: ExternalWorkoutImport.ride(from: $0),
                    externalWorkoutUUID: $0.id,
                    externalSourceName: $0.source.name
                )
            },
            provenance: .externalImport
        )
    }

    /// 已经导入过的第三方 workout UUID，供导入前去重。
    func importedExternalWorkoutUUIDs() throws -> Set<UUID> {
        var descriptor = FetchDescriptor<RideModel>(
            predicate: #Predicate { $0.externalWorkoutUUID != nil }
        )
        descriptor.propertiesToFetch = [\.externalWorkoutUUID]
        return Set(try context.fetch(descriptor).compactMap(\.externalWorkoutUUID))
    }

    // MARK: - 去重插入

    private func insert(_ pending: [PendingRide], provenance: RideProvenance) throws -> RideSaveResult {
        var existing = try context.fetch(FetchDescriptor<RideModel>())
        var inserted: [RideModel] = []
        var replacedHealthUUIDs: [UUID] = []
        for item in pending where item.ride.duration >= RideDetectionPolicy.minimumRideDuration {
            let ride = item.ride
            let overlapping = existing.filter { overlapSeconds(of: $0, with: ride) > 0 }
            // 自动检测最弱：任何重叠都算冲突。其余两种允许边界擦碰共存。
            let conflicting = provenance.isAutoDetected
                ? overlapping
                : overlapping.filter { overlapSeconds(of: $0, with: ride) >= Self.conflictOverlapSeconds }
            if !conflicting.isEmpty {
                let replaceable = conflicting.filter { canReplace($0, with: ride, provenance: provenance) }
                let blocked = conflicting.count != replaceable.count
                if blocked { continue }
                for model in replaceable {
                    // 只删本 app 写进健康的那条；第三方写的不归我们删（那边恒为 nil）。
                    if let uuid = model.healthKitWorkoutUUID {
                        replacedHealthUUIDs.append(uuid)
                    }
                    context.delete(model)
                    existing.removeAll { $0.rideID == model.rideID }
                }
            }
            let model = RideMapping.makeModel(
                from: ride,
                autoDetected: provenance.isAutoDetected,
                externalWorkoutUUID: item.externalWorkoutUUID,
                externalSourceName: item.externalSourceName
            )
            context.insert(model)
            existing.append(model)
            inserted.append(model)
        }
        try context.save()
        return RideSaveResult(inserted: inserted, replacedHealthWorkoutUUIDs: replacedHealthUUIDs)
    }

    /// 新记录能否顶掉这条已有记录。顶不掉就整条放弃（`blocked`），不做部分覆盖。
    private func canReplace(_ model: RideModel, with ride: Ride, provenance: RideProvenance) -> Bool {
        switch provenance {
        case .autoDetected:
            // 只在明显更完整时替换旧的自动记录，避免同一段运动被反复写进 Apple 健康；
            // 绝不覆盖手动记录或导入记录。
            return model.isAutoDetected
                && model.activityTypeRaw == ride.activityType.rawValue
                && isBetterAutoDetectedRide(ride, than: model)
        case .externalImport:
            // 设备实测顶掉本 app 的估算；碰上手动实录或另一条导入记录则整条放弃。
            return model.isAutoDetected
        case .manual:
            // 用户实录是该时段的事实来源：顶掉估算记录，也顶掉同段的导入记录
            // （本 app 实录带暂停信息，比外部记录更准）。碰上已有手动记录才放弃。
            return model.isAutoDetected || model.externalWorkoutUUID != nil
        }
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
