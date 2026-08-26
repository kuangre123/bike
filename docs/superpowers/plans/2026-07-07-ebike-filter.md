# 疑似电动车过滤 — 实现计划

- 日期：2026-07-07（2026-08-26 执行完毕：T1–T5 全部落地；域测试 14/14 绿，app 全量类型检查零错误。真机行为验证与 BikeTests 模拟器全量回归待用户侧 Xcode 执行——本机沙箱无法跑模拟器测试）

- 设计：`docs/superpowers/specs/2026-07-07-ebike-filter-design.md`（已确认）
- 定位：v-next，不进 1.1/1.2 发版

## 任务拆分（按序执行，每步测试通过再进下一步）

### T1 域纯函数 `isSuspectedEBike` + 单测（TDD）

- 新文件 `Packages/CyclingDomain/Sources/CyclingDomain/EBikeSuspicion.swift`：
  - `EBikeHeuristic` 常量组：`minDurationSeconds=300`、`minAvgSpeedMps=5.6`、`maxCoefficientOfVariation=0.30`、`movingThresholdMps=1.4`。
  - `public func isSuspectedEBike(activityType:durationSeconds:speedSamplesMps:) -> Bool`。
  - 规则（全满足才 true）：cycling；时长 ≥ 300s；过滤 `speed > 1.4` 后移动样本 ≥ 2；均速 ≥ 5.6 m/s（取等命中）；CV = 标准差/均值 ≤ 0.30（取等命中）。
- 新测试 `Tests/CyclingDomainTests/EBikeSuspicionTests.swift`：匀速电动车 true；起伏蹬踏 false；短途 false；无 GPS false；非骑行 false；边界取等（均速恰好 5.6、CV 恰好 0.30 → true）；全停顿样本 false。

### T2 `RideModel.excludedAsEBike` + 派生疑似 + 排除/恢复语义

- `RideModel` 加 `var excludedAsEBike: Bool = false`（默认值，轻量迁移安全）。
- App 层派生辅助（RideMapping 或 RideModel extension）：`isSuspectedEBike(ride)` = 解码 `routeData` 取逐点 `speedMps` + `duration` + `activityType` 调域函数；受设置开关控制。
- 排除：置 `excludedAsEBike = true`；若 `healthKitWorkoutUUID != nil` → `HealthService.deleteWorkout(uuid:)`（保留 UUID 记录「曾写过健康」，另存或据 writeBack 判断重写）。
- 恢复：置 false；若 `healthWriteBack` 开且原先写过健康 → 重新 `saveWorkout` 并回填新 UUID。

### T3 统计聚合过滤

- `StatsSummaryView` / `HomeHeroCard` 等聚合处：过滤 `!$0.excludedAsEBike`。

### T4 UI

- 时间线行：派生疑似 → 徽标「疑似电动车」。
- 行左滑加「标为电动车」；`RideDetailView` 加对应按钮；已排除条目「恢复」。
- 底部折叠区「已排除（电动车）」，灰显。
- 设置：开关「自动标注疑似电动车」（`UserDefaults` key `ebikeAutoFlag`，默认开）。关闭只隐藏徽标，不影响已排除状态。

### T5 App 层测试 + 回归

- 排除/恢复翻转、统计重算；`xcodegen generate` 后跑 BikeTests 全量。

## 验证

- `swift test`（CyclingDomain）全绿。
- iOS 模拟器 BikeTests 全绿。
- 手动：模拟含匀速高速轨迹的记录出现徽标；排除后统计减少、健康删除；恢复还原。
