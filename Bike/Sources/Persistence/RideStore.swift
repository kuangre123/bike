import Foundation
import SwiftData
import CyclingDomain

/// 包装 `ModelContext`：保存对账后的骑行（按时间去重）、查询。
/// 普通 struct（非 @MainActor）—— 只在主线程（UI / 检测管线 hop 后）同步调用。
struct RideStore {
    let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    /// 保存一批领域 Ride；与已存在记录时间重叠的跳过（避免回溯对账重复写入）。
    /// 返回实际插入条数。
    @discardableResult
    func save(_ rides: [Ride]) throws -> Int {
        let existing = try context.fetch(FetchDescriptor<RideModel>())
        var inserted = 0
        for ride in rides {
            let overlaps = existing.contains { ride.start < $0.endDate && $0.startDate < ride.end }
            if overlaps { continue }
            context.insert(RideMapping.makeModel(from: ride))
            inserted += 1
        }
        try context.save()
        return inserted
    }

    /// 全部骑行，按开始时间倒序。
    func allRides() throws -> [RideModel] {
        try context.fetch(
            FetchDescriptor<RideModel>(sortBy: [SortDescriptor(\.startDate, order: .reverse)])
        )
    }
}
