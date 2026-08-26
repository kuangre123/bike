# 疑似电动车过滤 — 设计（Design Spec）

- 日期：2026-07-07
- 状态：已实现（2026-08-26；待真机验证与阈值按实测回调）
- 版本定位：v-next 功能，**不进正在上架的 1.1/1.2**

## 背景与问题

「快乐轻骑」被动记录会把**电动自行车/电瓶车**的骑行也自动记成「骑行」，而用户不想要电动车数据。iPhone 的 CoreMotion 运动历史（`CMMotionActivity`）只分「骑行/汽车」，分不清电动车 vs 脚踏车；靠陀螺仪左右摆动做实时分类不可行（手机放置方式主导信号、需高频采样破坏零耗电模型、无标注数据）。

因此采用**速度启发式软提示**：把「长时间、高速、速度方差极小」的骑行标注为「疑似电动车」，由用户一键排除。判定不追求全自动准确，只做保守建议，最终由用户确认。

## 目标 / 非目标

**目标**
- 对**有 GPS 轨迹**的骑行记录，按保守启发式派生「疑似电动车」标记并在 UI 提示。
- 用户可**一键排除**疑似记录：排除后不计入统计、列表收起灰显、若已写入 Apple 健康则从健康删除。
- 排除**可撤销**（恢复后重新计入统计并写回健康）。

**非目标（本期不做）**
- 不做陀螺仪/加速度计原始信号的机器学习分类。
- 不对 **motionOnly（无 GPS 轨迹）** 的骑行自动判定（信号不足、易误判；这类由用户手动删除）。
- 阈值不做成用户可调（仅代码内常量）；仅提供一个「自动标注疑似电动车」总开关。

## ① 判定启发式（CyclingDomain 纯函数）

新增纯函数，放 `Packages/CyclingDomain/Sources/CyclingDomain/`（新文件 `EBikeSuspicion.swift`），无 CoreLocation/CoreMotion 依赖，可单测。

签名（示意）：

```
public func isSuspectedEBike(
    activityType: ActivityType,
    durationSeconds: TimeInterval,
    speedSamplesMps: [Double]   // 来自 route 的逐点速度；空表示无 GPS
) -> Bool
```

判定规则（**三条全满足**才返回 true）：
1. `activityType == .cycling` 且 `speedSamplesMps` 非空（有 GPS 轨迹）。
2. `durationSeconds >= 300`（≥ 5 分钟，样本足够）。
3. 去掉停顿样本（`speed > 1.4 m/s` ≈ 5 km/h 视为移动）后：
   - 移动样本均速 `>= 5.6 m/s`（≈ 20 km/h），且
   - 移动样本速度**变异系数**（标准差/均值）`<= 0.30`。

阈值以命名常量声明（`minDuration=300`、`minAvgSpeedMps=5.6`、`maxCV=0.30`、`movingThresholdMps=1.4`）。**均为保守初值，需按用户真实骑行/电动车数据回调**——软提示，宁可漏判不误判真骑行。

## ② 数据模型与排除语义

- `RideModel` 增加 `var excludedAsEBike: Bool = false`（带默认值，SwiftData 轻量迁移安全）。
- 「疑似电动车」是**派生量**：由存储的 `routeData`（解码出逐点速度）+ 时长 + 类型实时计算，不落库。
- 只持久化用户的**排除决定**（`excludedAsEBike`）。
- 排除后：
  - 移出**本周统计**与**首页汇总**（`StatsSummaryView` / `HomeHeroCard` 等聚合处过滤 `excludedAsEBike == true`）。
  - 时间线里从主列表移到底部**「已排除（电动车）」折叠区**，灰显，带「恢复」动作。

## ③ Apple 健康交互

- 排除时：若 `healthKitWorkoutUUID != nil`，用现有 `HealthService`（`matchingWorkouts` + 删除）把该 workout 从 Apple 健康删除；置空/保留 UUID 由实现决定（建议保留 UUID 以便恢复时判断是否需重写）。幂等。
- 恢复时：若原先写过健康（且用户 `healthWriteBack` 开启），重新 `saveWorkout` 写回，并回填新的 `healthKitWorkoutUUID`。
- 仅在有 UUID / 写回开启时才动健康；未写过健康的记录排除只改本地标记。

## ④ UI

- **时间线行**：命中启发式（派生为疑似）的骑行行显示小徽标「疑似电动车」。
- **排除动作**：行左滑「标为电动车」→ 排除；`RideDetailView` 详情页放一个对应按钮。
- **已排除区**：底部可折叠「已排除（电动车）」分组，条目灰显，左滑「恢复」。
- **设置**：新增开关「自动标注疑似电动车」（默认开）。关掉后不再显示疑似徽标；已排除状态不受开关影响。

## ⑤ 测试

- **CyclingDomain 单测**（纯函数）：
  - 匀速 22 km/h、低方差、时长 10 分 → `true`。
  - 起伏蹬踏（含停顿、方差大）→ `false`。
  - 高速但短途（< 5 分）→ `false`。
  - 无 GPS 样本（motionOnly）→ `false`。
  - 边界：CV 恰好 0.30 / 均速恰好 20 km/h 的取等行为明确。
- **App 层**：排除/恢复能翻转 `excludedAsEBike`、聚合统计重算、健康删除/写回被调用（可用现有 Health 幂等基础设施与测试替身）。

## 范围与后续

- 本功能独立于当前 1.1/1.2 发版，单独走 spec → plan → 实现 → 发版。
- 阈值上线后按用户实测反馈（哪些被正确/错误标注）迭代收敛。
- 后续可选增强（本期不做）：motionOnly 记录的估算均速粗判、「自动排除」而非仅提示的可选模式。
