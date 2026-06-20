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
        let existing = try context.fetch(FetchDescriptor<RideModel>())
        var inserted: [RideModel] = []
        for ride in rides {
            let overlaps = existing.contains { ride.start < $0.endDate && $0.startDate < ride.end }
            if overlaps { continue }
            let model = RideMapping.makeModel(from: ride, autoDetected: autoDetected)
            context.insert(model)
            inserted.append(model)
        }
        try context.save()
        return inserted
    }

    /// 全部运动，按开始时间倒序。
    func allRides() throws -> [RideModel] {
        try context.fetch(
            FetchDescriptor<RideModel>(sortBy: [SortDescriptor(\.startDate, order: .reverse)])
        )
    }
}
