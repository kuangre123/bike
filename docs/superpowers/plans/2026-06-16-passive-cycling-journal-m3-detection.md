# 被动骑行日志 — M3：检测接线 Implementation Plan

> 状态：已实现并验证（编译 + 模拟器启动）。真实运动/定位数据需真机。

**Goal:** 把 CoreMotion 运动历史（基线）+ 显著位置变化唤醒 + 实时 GPS（增强）+ 后台对账接成一条检测管线，产出的骑行经领域对账落库。

**Tech Stack:** CoreMotion / CoreLocation / BackgroundTasks / Swift 6 strict concurrency。

## 文件
```
Packages/CyclingDomain/Sources/CyclingDomain/MotionSegmentBuilder.swift  # CMMotionActivity 切分（纯逻辑，可测）
Bike/Sources/Detection/PermissionsManager.swift      # 运动+定位授权
Bike/Sources/Detection/MotionHistoryService.swift    # 回溯查询 -> 骑行时段
Bike/Sources/Detection/LiveRideTracker.swift         # 骑行时全功率 GPS -> TrackedRide
Bike/Sources/Detection/LocationWakeService.swift     # 显著位置变化唤醒
Bike/Sources/Detection/RideDetectionCoordinator.swift# 编排 + 对账 + 落库
Bike/Sources/Detection/BackgroundReconcileTask.swift # BGTaskScheduler 周期对账
Bike/Sources/UI/SettingsView.swift                   # 权限状态 + 手动对账
```
project.yml 增：运动/定位用途串、UIBackgroundModes(location/fetch/processing)、BGTaskSchedulerPermittedIdentifiers。

## 检测流程
1. `start()`（幂等）：请求权限、`startMonitoringSignificantLocationChanges` 唤醒、`startActivityUpdates` 实时活动、首次对账。
2. 实时活动=骑行且置信≥medium → `LiveRideTracker.start` 全功率 GPS；活动转非骑行 → `stop` 产出 `TrackedRide` 入 pending。
3. 唤醒 / tracked 完成 / 后台任务 → `runReconciliation`：回溯 7 天运动历史 → `mergeCyclingSegments`(maxGap 60s, minDuration 90s) → `RideReconciler.reconcile`(+pending tracked) → `RideStore.save`（时间去重）。

## 关键决策（Swift 6 strict concurrency）
- 服务标 `@MainActor`；CL 代理方法 `nonisolated` + `MainActor.assumeIsolated`（CL 在主线程回调）。
- CMMotionActivity（非 Sendable）在回调线程内即映射成 `RawActivitySample`（Sendable）再跨 continuation。
- BGTask（非 Sendable）用 `@unchecked Sendable` Box 桥接进 Task。
- 切分逻辑抽成纯函数 `buildCyclingSegments` 放领域包，6 个单测覆盖（本机可跑）。

## 已知限制（留待后续）
- 若某次骑行先以 `.motionOnly` 落库，随后 tracked 到达，因时间去重不会「升级」为 `.merged`。后续里程碑处理升级/合并。
- 真机才有真实运动分类与后台唤醒；模拟器仅验证编译与不崩溃。

## 验证
- 领域：`swift test`（含 6 个切分测试）26 项全过。
- app：`xcodebuild ... build` 成功；模拟器启动不崩溃，设置页/权限/手动对账接线就位。
