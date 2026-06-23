import Foundation
import SwiftData
import CyclingDomain

/// 包装 `ModelContext`：保存对账后的运动（按时间去重）、查询。
/// 普通 struct（非 @MainActor）—— 只在主线程（UI / 检测管线 hop 后）同步调用。
struct RideStore {
    let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    /// 保存一批领域 Ride；与已存在记录时间重叠的跳过。返回实际插入的模型。
    @discardableResult
    func save(_ rides: [Ride], autoDetected: Bool) throws -> [RideModel] {
        var existing = try context.fetch(FetchDescriptor<RideModel>())
        var inserted: [RideModel] = []
        for ride in rides where ride.duration >= RideDetectionPolicy.minimumRideDuration {
            let overlapping = existing.filter { ride.start < $0.endDate && $0.startDate < ride.end }
            if !overlapping.isEmpty {
                let replaceable = overlapping.filter {
                    autoDetected
                        && $0.isAutoDetected
                        && $0.activityTypeRaw == ride.activityType.rawValue
                        && isBetterAutoDetectedRide(ride, than: $0)
                }
                let blocked = overlapping.count != replaceable.count
                if blocked { continue }
                for model in replaceable {
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
        return inserted
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
