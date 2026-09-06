import Foundation
import SwiftData
import CyclingDomain

/// 把 Apple 健康里**别的 app / 设备**写的运动导进本地库。
///
/// 不逐家对接 SDK：Garmin Connect、华为运动健康、Zepp（小米 / Amazfit）、Wahoo、Keep、Strava
/// 都会把运动写进 Apple 健康，所以读健康就等于同时支持了它们——多一家新 app 也不用改代码。
///
/// 两条铁律：
/// 1. **只读不删**。导入记录的 workout 是对方写的，本 app 的删除 / 排除 / 合并绝不碰它
///    （所以 `externalWorkoutUUID` 和 `healthKitWorkoutUUID` 分开存）。
/// 2. **不写回健康**。那条 workout 本来就在健康里，写回等于制造重复。
@MainActor
@Observable
final class ExternalWorkoutImporter {
    /// 健康里发现的第三方来源，供设置页勾选。
    private(set) var sources: [DiscoveredSource] = []
    private(set) var isWorking = false
    /// 上一次扫描 / 导入的结果文案。
    private(set) var message: String?
    /// 是否已经扫描过一次（用来区分「还没扫」和「扫了但没有」）。
    private(set) var hasScanned = false

    struct DiscoveredSource: Identifiable, Equatable {
        let source: ExternalWorkoutSource
        /// 最近一年里这个来源写了多少条本 app 认识的运动。
        let count: Int
        let latest: Date
        var id: String { source.id }
        var name: String { source.name }
    }

    @ObservationIgnored private let container: ModelContainer
    @ObservationIgnored private let health: HealthService

    init(container: ModelContainer, health: HealthService = HealthService()) {
        self.container = container
        self.health = health
    }

    /// 扫描健康里有哪些第三方来源写过运动。
    ///
    /// HealthKit 的读授权是不可见的：用户拒绝时查询只会返回空，和「真的没有别的设备」
    /// 长得一模一样。所以这里不谎报「已拒绝」，扫不到就照实说扫不到，并提示去哪儿开。
    func discoverSources() async {
        guard !isWorking else { return }
        isWorking = true
        defer { isWorking = false }
        message = nil
        _ = await health.requestWorkoutReadAuthorization()
        sources = await health.externalWorkoutSources().map {
            DiscoveredSource(source: $0.source, count: $0.count, latest: $0.latest)
        }
        hasScanned = true
    }

    /// 导入所有已勾选来源里还没导过的记录。
    @discardableResult
    func importEnabled() async -> Int {
        guard !isWorking else { return 0 }
        isWorking = true
        defer { isWorking = false }
        message = nil

        let enabled = ExternalSourcePreferences.enabledSourceIDs
        guard !enabled.isEmpty else {
            message = String(localized: "先勾选要导入的来源。")
            return 0
        }
        _ = await health.requestWorkoutReadAuthorization()

        let context = ModelContext(container)
        let store = RideStore(context: context)
        let alreadyImported = (try? store.importedExternalWorkoutUUIDs()) ?? []

        // 先拿概要（便宜），筛完再补路线和心率（每条一次查询，贵）。
        let candidates = await health.externalWorkoutSummaries(sourceIDs: enabled)
        let importable = ExternalWorkoutImport.importable(
            candidates,
            enabledSourceIDs: enabled,
            alreadyImported: alreadyImported,
            dismissed: Set(ExternalSourcePreferences.dismissedWorkoutIDs)
        )
        guard !importable.isEmpty else {
            message = String(localized: "没有新的记录可导入。")
            return 0
        }

        let detailed = await health.enrich(importable)
        let result = (try? store.saveImported(detailed)) ?? .empty

        // 设备实测顶掉了本 app 之前的估算记录：把那条**我们自己**写进健康的 workout 删掉，
        // 否则健康里同一段运动会同时留着 Garmin 的和我们估的两条。
        for uuid in result.replacedHealthWorkoutUUIDs {
            _ = await health.deleteWorkout(uuid: uuid)
        }

        let inserted = result.inserted.count
        let skipped = detailed.count - inserted
        message = Self.summary(inserted: inserted, skipped: skipped)
        return inserted
    }

    /// 结果文案。跳过的都是和已有手动记录 / 已导入记录撞了时段的。
    static func summary(inserted: Int, skipped: Int) -> String {
        if inserted == 0 {
            return String(localized: "没有新的记录可导入。")
        }
        if skipped > 0 {
            return String(localized: "已导入 \(inserted) 条，另有 \(skipped) 条与已有记录重叠，已跳过。")
        }
        return String(localized: "已导入 \(inserted) 条记录。")
    }
}
