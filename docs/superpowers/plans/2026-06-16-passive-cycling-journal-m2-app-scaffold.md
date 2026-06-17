# 被动骑行日志 — M2：app 骨架 + SwiftData + 时间线 UI

> **For agentic workers:** REQUIRED SUB-SKILL: superpowers:executing-plans。本机无完整 Xcode，Swift 编译/模拟器在用户的 Xcode 环境完成。

**Goal:** 用 XcodeGen 立起 iOS app 工程，集成 `CyclingDomain` 本地包，用 SwiftData 持久化骑行，时间线 UI 按天分组展示。DEBUG 下可注入示例数据，在 Xcode 模拟器直接看 UI（M3 接真实检测前）。

**Architecture:** 单 iOS app target「Bike」，依赖本地包 `CyclingDomain`。领域 `Ride` → `RideMapping` → SwiftData `RideModel` 持久化；UI 用 `@Query` 读取按天分组。

**Tech Stack:** XcodeGen / SwiftUI / SwiftData / iOS 17 / Swift 6（strict concurrency complete）。

## ⚠️ 环境
- 本机：`xcodegen generate` 可校验工程配置（不需完整 Xcode）。
- 你的 Xcode 环境：`xcodegen generate && open Bike.xcodeproj`，选模拟器 Run。

## 文件结构
```
project.yml                                          # XcodeGen 工程定义
Bike/Sources/App/BikeApp.swift                       # @main + modelContainer
Bike/Sources/Persistence/RideModel.swift             # @Model 持久化骑行
Bike/Sources/Persistence/RoutePointDTO.swift         # 路线点（JSON 进 routeData）
Bike/Sources/Persistence/RideMapping.swift           # 领域 Ride <-> RideModel
Bike/Sources/Persistence/RideStore.swift             # 保存去重 / 查询
Bike/Sources/UI/RideTimelineView.swift               # 时间线（按天分组）
Bike/Sources/UI/RideRowView.swift                    # 单行
Bike/Sources/Support/Formatters.swift                # 时长/距离/卡路里/日期格式化
Bike/Sources/Support/SampleData.swift                # #if DEBUG 示例数据
Bike/Sources/Resources/Assets.xcassets/...           # AppIcon + AccentColor
Bike/Tests/RideMappingTests.swift                    # 映射单测
```

## 关键决策（含 blind-write 避坑）
- **RideModel 用 `rideID` 而非 `id`**：SwiftData `PersistentModel` 已经通过 `Identifiable` 提供 `id`（= PersistentIdentifier），再声明 `id` 属性会冲突。
- **路线存为 `routeData: Data?`（JSON `[RoutePointDTO]`）**：避开 SwiftData 关系 / Codable 数组属性的不确定性；M5 渲染地图时解码。
- **保存去重**：按时间区间重叠跳过，避免 M3 回溯对账反复写同一次骑行。
- **RideStore 为普通 struct（非 @MainActor）**，方法同步；只在主线程 UI / M3 检测管线 hop 到主线程后调用，规避 strict-concurrency 报错。
- **DEBUG「示例」按钮**注入 `SampleData`，让 UI 在没有真实检测时也能在 Xcode 里验证。
- **iOS 17 起步**：SwiftData 硬要求（高于 ai-cleaner 的 16）。

## 任务
- [ ] 写 `project.yml` + 资源目录 + 资产目录
- [ ] `RideModel` + `RoutePointDTO`
- [ ] `RideMapping` + `RideMappingTests`
- [ ] `RideStore`（save 去重 / allRides）
- [ ] `BikeApp` 入口 + `.modelContainer(for:)`
- [ ] `Formatters` + `RideRowView` + `RideTimelineView`
- [ ] `SampleData`（DEBUG）
- [ ] 本地 `xcodegen generate` 通过
- [ ] 你的 Xcode：build + 模拟器 Run，点「示例」看到按天分组列表

## 验证
- 本地：`xcodegen generate` 退出码 0 = 配置 OK。
- Xcode：模拟器跑起来，空态显示「还没有骑行记录」；点右上「示例」后出现今天/昨天等分组、含「merged」带距离卡路里、「motionOnly」显示「无路线」。

## 下一步
M3：CoreMotion 基线回溯 + 定位唤醒 + LiveRideTracker + BackgroundCoordinator（需真机）。
