# 被动骑行日志 (Passive Cycling Journal) — 设计文档

- 日期：2026-06-16
- 状态：已通过 brainstorming，待出实现计划
- 平台：iOS (iPhone) + watchOS (Apple Watch)

## 1. 概述

一个**被动**骑行日志 app。核心承诺：**永不漏记任何一次骑行，且完全不需要用户手动开始**。

- iPhone 的运动协处理器（CoreMotion）被动检测骑行 = **基线层**，可回溯过去几天、零额外耗电、即使用户拒绝定位也照常记录。
- 骑行进行中自动唤醒采 GPS = **增强层**，补上距离、均速、卡路里、路线轨迹。
- Apple Watch 补心率，让卡路里更准。
- 检测到的骑行可写回 **Apple 健康**（含 GPS 路线轨迹）。
- **优雅降级**：权限给得越多数据越丰富；只给最少权限也照常记录（仅时长/时间/次数）。

## 2. 目标 / 非目标

**目标 (v1)：**
- 自动、零操作地检测并记录每次户外骑行（含短途，正是 Apple Watch 经常漏检的场景）
- 每次骑行尽可能记录：时长、时间段、距离、均速、卡路里、GPS 路线、（手表）均心率
- 骑行结束推送通知
- 写回 Apple 健康（`HKWorkout` + 路线），默认开
- 日 / 周统计与趋势

**非目标 (v1)：**
- 手动「开始/结束骑行」的 workout 模式（这是被动日志，不是 Strava 替代）
- 社交 / 分享 / 排行榜
- 跨设备云同步（CloudKit）→ 留 v2
- 训练计划 / 教练 / 配速指导
- 室内骑行台检测（无 GPS、运动特征不同，超出 v1）

## 3. 核心决策（来自 brainstorming）

| 维度 | 决策 |
|------|------|
| 核心定位 | 被动骑行日志 |
| 记录粒度 | 完整：时长/时间 + 距离/速度/卡路里 + GPS 路线 |
| 架构 | 混合（运动历史基线 + GPS 增强），优雅降级 |
| 平台 | iPhone + Apple Watch |
| 结束通知 | 是 |
| 写回 Apple 健康 | 是，默认开，含路线；绿环计入待实测 |
| 存储 | 本地 SwiftData（v1） |

## 4. 架构

混合双层：

```
┌─────────────────────────── iPhone ───────────────────────────┐
│                                                               │
│  基线层（永远在，被动）                                          │
│    CMMotionActivityManager  ──回溯查询──►  骑行时段             │
│    （零耗电、可回溯过去 7 天、不依赖定位）                        │
│                                                               │
│  增强层（骑行进行时）                                            │
│    显著位置变化 ──唤醒──► 确认骑行 ──► 全功率 GPS                │
│    （距离/均速/路线，仅在检测到骑行时运行，按需耗电）             │
│                                                               │
│  RideReconciler：合并两层、去重、补缺口                          │
│         │                                                     │
│         ▼                                                     │
│    RideStore (SwiftData) ──► HealthKit 写回 ──► 通知 / UI       │
└───────────────────────────────────────────────────────────────┘
            ▲ WatchConnectivity（协调心率采集 / 同步）
┌─────────── Apple Watch ───────────┐
│  HKWorkoutSession 采心率           │
│  complication：今日骑行时长         │
└───────────────────────────────────┘
```

## 5. 组件（iPhone）

| 组件 | 职责 | 依赖 |
|------|------|------|
| `MotionHistoryService` | 查 `CMMotionActivityManager` 的骑行时段（基线，可回溯） | CoreMotion |
| `LocationWakeService` | `startMonitoringSignificantLocationChanges` 在骑行开始时唤醒被挂起的 app | CoreLocation |
| `LiveRideTracker` | 确认骑行后启动全功率 GPS，采速度/距离/路线，骑行停止即结束 | CoreLocation, CoreMotion |
| `RideReconciler` | 按时间重叠合并「基线时段」与「GPS 实采骑行」，去重、补缺口、过滤误判 | — |
| `RideStore` | SwiftData 持久化 | SwiftData |
| `HealthKitService` | 写 `HKWorkout(.cycling)` + 路线；读心率 | HealthKit |
| `NotificationService` | 骑行结束本地推送 | UserNotifications |
| `BackgroundCoordinator` | 注册 `BGTaskScheduler` + 显著位置变化，触发回溯对账 | BackgroundTasks |
| `WatchSessionManager` | 与手表同步、协调心率采集 | WatchConnectivity |
| SwiftUI 界面 | ① 骑行时间线 ② 骑行详情（地图+数据） ③ 统计趋势 ④ 设置/权限 | SwiftUI, MapKit |

## 6. 数据模型

`Ride`（SwiftData `@Model`）：
- `id: UUID`
- `startDate: Date`
- `endDate: Date`
- `duration: TimeInterval`（派生）
- `distanceMeters: Double?`（无 GPS 时为 nil）
- `avgSpeedMps: Double?`
- `calories: Double?`
- `confidence: Int`（CoreMotion 置信度 0/1/2）
- `source: RideSource`（`.motionOnly` / `.gpsTracked` / `.merged`）
- `route: [RoutePoint]?`（GPS 轨迹点：经纬度 + 时间戳 + 瞬时速度）
- `avgHeartRate: Double?`（手表）
- `healthKitWorkoutUUID: UUID?`（写回健康后回填，用于去重/删除联动）
- `createdAt: Date`

## 7. 检测算法

**基线（回溯）：**
1. `queryActivityStarting(from:to:)` 拉取时间窗内活动
2. 取 `cycling == true && confidence >= medium` 的时段
3. 相邻同类时段合并；过滤短于最小阈值的噪声
4. 最小骑行时长：**默认 60–90 秒**（可配置）——刻意调低以捕捉 Apple Watch 漏掉的短途

**实时（增强）：**
1. 显著位置变化唤醒 app
2. 查 CoreMotion 当前/近期活动 → 若为 cycling 则启动全功率 GPS
3. 持续追踪，直到 cycling 停止（去抖：连续约 2 分钟非骑行判定为结束）
4. 算时长/距离/均速/卡路里（MET 公式，有心率则用心率修正）
5. （若手表可达）通知手表采心率

**合并 / 去重（RideReconciler）：**
- 按时间重叠匹配「基线时段」与「GPS 实采骑行」
- 重叠则保留 GPS 版本（数据更丰富），标 `.merged`
- 未被实采覆盖的基线时段 → 存为 `.motionOnly`（仅时长/时间）

**误判过滤：**
- 置信度阈值（>= medium）
- GPS 均速合理性（骑行约 8–35 km/h，排除电动车/汽车）

## 8. 权限与能力

- `NSMotionUsageDescription`（运动）
- `NSLocationAlwaysAndWhenInUseUsageDescription` + `NSLocationWhenInUseUsageDescription`（定位，需 Always 才能后台唤醒采 GPS）
- `NSHealthUpdateUsageDescription` + `NSHealthShareUsageDescription`（健康读写）
- 通知授权
- Background Modes：`location`、`background processing`/`fetch`
- 应用内需有清晰的权限解释页（Always 定位审核严，必须说明用途）

## 9. HealthKit 集成

- 用 **`HKWorkoutBuilder`**（iOS 17+ 现代 API）建 `.cycling` workout
- 挂样本：`distanceCycling`、`activeEnergyBurned`、`heartRate`（手表）
- 路线用 **`HKWorkoutRouteBuilder`** 附 `CLLocation` 轨迹 → Apple 健身/健康里可见地图
- 来源显示为本 app；回填 `healthKitWorkoutUUID` 以便去重与删除联动
- **活动圆环**：写入的 `activeEnergyBurned` 贡献红环（Move）；绿环（Exercise / `appleExerciseTime` 系统计算类型）**第三方写入的 workout 不保证计入** → 规划阶段实测确认

## 10. Apple Watch 端

- 轻量：今日骑行一览 / 当前骑行；`HKWorkoutSession` + `HKLiveWorkoutBuilder` 采心率
- 表盘 complication：今日骑行时长
- **头号待验证风险**：watchOS 不允许后台静默启动 workout 采心率。现实模型为「iPhone 检测到骑行 → 经 WatchConnectivity 触发手表采集」或退化为「尽力而为 / 需用户在表上轻点一次」。规划阶段验证可行性，否则手表降级为 v2。

## 11. 风险与缓解

| 风险 | 缓解 |
|------|------|
| Always 定位审核严 / 用户拒绝 | 强用途说明 + 应用内解释页；拒绝则退回基线（仍可记录时长/时间） |
| 超短途骑行不触发实时 GPS | 基线兜底（有时长无路线），可接受 |
| 手表被动采心率受限 | 见 §10；最坏降级为 v2 |
| 检测误判（电动车/汽车） | 置信度阈值 + GPS 均速合理性过滤 |
| 与 Apple Watch 自动检测的同一次骑行重复 | 按时间窗去重；本 app 主攻手表漏检的短途，冲突少 |

## 12. v2 / 延后

- CloudKit 跨设备同步
- 变现（freemium：基础日志免费，路线图/统计趋势付费）
- 手动骑行兜底入口
- 室内骑行台支持
- 更可靠的手表被动检测

## 13. 技术栈

- Swift + SwiftUI + SwiftData
- CoreMotion、CoreLocation、HealthKit、WatchConnectivity、UserNotifications、BackgroundTasks、MapKit
- iOS 17+ / watchOS 10+（HKWorkoutBuilder 现代 API、SwiftData）
- XcodeGen（`project.yml`）驱动，与用户其他 app 工程保持一致
- App 名称：待定（目录暂名 `bike`）
