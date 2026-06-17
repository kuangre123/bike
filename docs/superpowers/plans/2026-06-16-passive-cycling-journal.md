# 被动骑行日志 (Passive Cycling Journal) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 一个被动检测并记录骑行的 iPhone app（M1 即可运行：CoreMotion 回溯检测骑行 → 存储 → 时间线展示），后续里程碑加 GPS 增强、HealthKit 写回、Apple Watch。

**Architecture:** 混合双层 —— CoreMotion 运动历史做基线（可回溯、零耗电），GPS 做增强（骑行时采距离/速度/路线）。纯逻辑（卡路里、分段、合并去重）与框架封装（CoreMotion/CoreLocation/HealthKit）分离，纯逻辑用 Swift Testing 在模拟器全覆盖，框架封装走协议+mock，真机行为单独验证。

**Tech Stack:** Swift 6 / SwiftUI / SwiftData / Swift Testing / CoreMotion / CoreLocation / HealthKit / WatchConnectivity / MapKit；XcodeGen 驱动工程；iOS 17+。

设计文档：`docs/superpowers/specs/2026-06-16-passive-cycling-journal-design.md`

---

## Prerequisites（环境，每个新 shell 跑一次）

本机 Xcode 装在非标准路径（`~/Downloads/Xcode-beta.app`），`xcode-select` 指向 CommandLineTools。**不改全局**，用环境变量临时指过去：

```bash
export DEVELOPER_DIR=/Users/sirchen/Downloads/Xcode-beta.app/Contents/Developer
cd /Users/sirchen/bike
```

下文所有 `xcodebuild` / `xcrun` / `xcodegen` 命令都假设你已在当前 shell 跑过上面两行。验证：

```bash
xcodebuild -version   # 期望: Xcode 27.0
```

测试目标设备统一用 `iPhone 17`（模拟器已存在）。

---

## File Structure（M0–M1 落地范围）

```
bike/
  project.yml                        # XcodeGen 工程定义
  .gitignore
  Bike/
    App/
      BikeApp.swift                  # @main 入口，注入 ModelContainer
      RootView.swift                 # 根视图（M1 = 时间线）
    Models/
      Ride.swift                     # SwiftData @Model + RideSource 枚举
      RoutePoint.swift               # 轨迹点值类型（M2 起用，M1 先建空壳）
    Detection/
      ActivitySample.swift           # 纯值类型：镜像 CMMotionActivity 关心的字段
      MotionActivitySegment.swift    # 纯值类型：一段连续骑行
      CyclingSegmentBuilder.swift    # 纯逻辑：samples -> segments（合并/过滤）
      CalorieCalculator.swift        # 纯逻辑：MET 公式
      RideReconciler.swift           # 纯逻辑：基线段 + GPS 骑行 合并去重
      MotionHistoryProviding.swift   # 协议
      MotionHistoryService.swift     # CMMotionActivityManager 实现（真机验证）
      RideJournal.swift              # 协调器：拉历史 -> 合并 -> 存库
    UI/
      RideListViewModel.swift        # 时间线 VM（可测）
      RideTimelineView.swift         # 列表
      RideRowView.swift              # 单行
  BikeTests/
    SmokeTests.swift
    RideTests.swift
    RideStoreTests.swift             # 注: RideStore 实现放在 Models/Ride.swift 同文件或独立 Store/
    CalorieCalculatorTests.swift
    CyclingSegmentBuilderTests.swift
    RideReconcilerTests.swift
    RideJournalTests.swift
    RideListViewModelTests.swift
```

> 决策：`RideStore` 放在 `Bike/Store/RideStore.swift`（CRUD 与模型分离，职责单一）。

---

## Milestone Roadmap

- **M0 工程脚手架** — XcodeGen 工程，能在模拟器构建 + 跑通一个冒烟测试。
- **M1 核心可运行 app** — 数据模型 + 纯检测逻辑 + CoreMotion 基线 + 极简时间线 UI。结果：装到真机能被动记录骑行（时长/时间/次数）。
- **M2 GPS 增强**（路线图，本计划末尾列要点，执行到此再展开） — 显著位置变化唤醒、全功率 GPS、距离/均速/卡路里/路线、后台对账。
- **M3 HealthKit + 通知**（路线图） — `HKWorkoutBuilder` + `HKWorkoutRouteBuilder` 写回；结束推送。
- **M4 Apple Watch**（路线图） — `HKWorkoutSession` 采心率 + complication + WatchConnectivity。
- **M5 统计趋势 UI**（路线图） — 日/周汇总、趋势图。

每个里程碑都是可运行可测的增量。本计划详写 **M0 + M1**；M2–M5 在末尾列出要点，做到时各自展开为完整任务计划。

---

## M0 — 工程脚手架

### Task 0.1: XcodeGen 工程 + app 骨架 + 冒烟测试

**Files:**
- Create: `project.yml`
- Create: `.gitignore`
- Create: `Bike/App/BikeApp.swift`
- Create: `Bike/App/RootView.swift`
- Create: `BikeTests/SmokeTests.swift`

- [ ] **Step 1: 写 `.gitignore`**

```gitignore
.DS_Store
/build
/DerivedData
*.xcodeproj
xcuserdata/
*.xcuserstate
.swiftpm
```

> 注：`project.yml` 是真源，`.xcodeproj` 由 XcodeGen 生成，故忽略。

- [ ] **Step 2: 写 `project.yml`**

```yaml
name: Bike
options:
  bundleIdPrefix: com.bochen
  deploymentTarget:
    iOS: "17.0"
  createIntermediateGroups: true
settings:
  base:
    SWIFT_VERSION: "6.0"
    DEVELOPMENT_TEAM: ""          # 模拟器无需；真机/上架时填
    TARGETED_DEVICE_FAMILY: 1     # iPhone-only（见 reference_ios_orientation_validation 教训）
    MARKETING_VERSION: "1.0"
    CURRENT_PROJECT_VERSION: "1"
targets:
  Bike:
    type: application
    platform: iOS
    sources:
      - Bike
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.bochen.bike
        INFOPLIST_KEY_UILaunchScreen_Generation: YES
        INFOPLIST_KEY_UIApplicationSceneManifest_Generation: YES
        INFOPLIST_KEY_UISupportedInterfaceOrientations: UIInterfaceOrientationPortrait
        INFOPLIST_KEY_NSMotionUsageDescription: "用于自动检测你的骑行，无需手动开始记录。"
  BikeTests:
    type: bundle.unit-test
    platform: iOS
    sources:
      - BikeTests
    dependencies:
      - target: Bike
schemes:
  Bike:
    build:
      targets:
        Bike: all
        BikeTests: [test]
    test:
      targets:
        - BikeTests
```

- [ ] **Step 3: 写 `Bike/App/BikeApp.swift`**

```swift
import SwiftUI

@main
struct BikeApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
        }
    }
}
```

- [ ] **Step 4: 写 `Bike/App/RootView.swift`**

```swift
import SwiftUI

struct RootView: View {
    var body: some View {
        Text("Bike")
    }
}
```

- [ ] **Step 5: 写 `BikeTests/SmokeTests.swift`**

```swift
import Testing

@Test func smoke() {
    #expect(1 + 1 == 2)
}
```

- [ ] **Step 6: 生成工程并构建**

```bash
xcodegen generate
xcodebuild build -project Bike.xcodeproj -scheme Bike \
  -destination 'platform=iOS Simulator,name=iPhone 17'
```
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 7: 跑冒烟测试**

```bash
xcodebuild test -project Bike.xcodeproj -scheme Bike \
  -destination 'platform=iOS Simulator,name=iPhone 17'
```
Expected: `** TEST SUCCEEDED **`，`smoke` 通过。

- [ ] **Step 8: 提交**

```bash
git add project.yml .gitignore Bike BikeTests
git commit -m "chore(m0): XcodeGen 工程骨架 + 冒烟测试"
```

---

## M1 — 核心可运行 app

### Task 1.1: `Ride` 数据模型 + `RideSource`

**Files:**
- Create: `Bike/Models/Ride.swift`
- Create: `BikeTests/RideTests.swift`

- [ ] **Step 1: 写失败测试 `BikeTests/RideTests.swift`**

```swift
import Testing
import Foundation
@testable import Bike

@Test func rideComputesDuration() {
    let start = Date(timeIntervalSince1970: 1_000)
    let end = Date(timeIntervalSince1970: 1_600)   // +10 分钟
    let ride = Ride(start: start, end: end, source: .motionOnly, confidence: 2)
    #expect(ride.duration == 600)
    #expect(ride.distanceMeters == nil)
    #expect(ride.source == .motionOnly)
}
```

- [ ] **Step 2: 跑测试确认失败**

```bash
xcodebuild test -project Bike.xcodeproj -scheme Bike \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:BikeTests/rideComputesDuration
```
Expected: FAIL（`Ride` 未定义）

- [ ] **Step 3: 写 `Bike/Models/Ride.swift`**

```swift
import Foundation
import SwiftData

enum RideSource: String, Codable {
    case motionOnly   // 仅 CoreMotion 基线（无路线）
    case gpsTracked   // 实时 GPS 采集
    case merged       // 基线被 GPS 覆盖后合并
}

@Model
final class Ride {
    var id: UUID
    var startDate: Date
    var endDate: Date
    var distanceMeters: Double?
    var avgSpeedMps: Double?
    var calories: Double?
    var confidence: Int           // CoreMotion 置信度 0/1/2
    var sourceRaw: String
    var avgHeartRate: Double?
    var healthKitWorkoutUUID: UUID?
    var createdAt: Date

    var duration: TimeInterval { endDate.timeIntervalSince(startDate) }
    var source: RideSource {
        get { RideSource(rawValue: sourceRaw) ?? .motionOnly }
        set { sourceRaw = newValue.rawValue }
    }

    init(start: Date, end: Date, source: RideSource, confidence: Int,
         distanceMeters: Double? = nil, avgSpeedMps: Double? = nil,
         calories: Double? = nil, avgHeartRate: Double? = nil) {
        self.id = UUID()
        self.startDate = start
        self.endDate = end
        self.sourceRaw = source.rawValue
        self.confidence = confidence
        self.distanceMeters = distanceMeters
        self.avgSpeedMps = avgSpeedMps
        self.calories = calories
        self.avgHeartRate = avgHeartRate
        self.healthKitWorkoutUUID = nil
        self.createdAt = Date()
    }
}
```

- [ ] **Step 4: 跑测试确认通过**

```bash
xcodebuild test -project Bike.xcodeproj -scheme Bike \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:BikeTests/rideComputesDuration
```
Expected: PASS

- [ ] **Step 5: 提交**

```bash
git add Bike/Models/Ride.swift BikeTests/RideTests.swift
git commit -m "feat(m1): Ride 模型 + RideSource"
```

---

### Task 1.2: `RideStore`（SwiftData CRUD + 按时间去重）

**Files:**
- Create: `Bike/Store/RideStore.swift`
- Create: `BikeTests/RideStoreTests.swift`

- [ ] **Step 1: 写失败测试 `BikeTests/RideStoreTests.swift`**

```swift
import Testing
import Foundation
import SwiftData
@testable import Bike

@MainActor
private func makeInMemoryStore() throws -> RideStore {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try ModelContainer(for: Ride.self, configurations: config)
    return RideStore(context: container.mainContext)
}

@MainActor
@Test func storeInsertsAndFetches() throws {
    let store = try makeInMemoryStore()
    store.insert(Ride(start: Date(timeIntervalSince1970: 0),
                      end: Date(timeIntervalSince1970: 600),
                      source: .motionOnly, confidence: 2))
    #expect(store.allRides().count == 1)
}

@MainActor
@Test func storeSkipsDuplicateOverlappingRide() throws {
    let store = try makeInMemoryStore()
    let a = Ride(start: Date(timeIntervalSince1970: 0),
                 end: Date(timeIntervalSince1970: 600),
                 source: .motionOnly, confidence: 2)
    store.insert(a)
    // 时间高度重叠的另一条 -> 视为重复，不插入
    let dup = Ride(start: Date(timeIntervalSince1970: 60),
                   end: Date(timeIntervalSince1970: 540),
                   source: .motionOnly, confidence: 1)
    store.insertIfNew(dup)
    #expect(store.allRides().count == 1)
}
```

- [ ] **Step 2: 跑测试确认失败**

```bash
xcodebuild test -project Bike.xcodeproj -scheme Bike \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:BikeTests/RideStoreTests
```
Expected: FAIL（`RideStore` 未定义）

- [ ] **Step 3: 写 `Bike/Store/RideStore.swift`**

```swift
import Foundation
import SwiftData

@MainActor
final class RideStore {
    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    func insert(_ ride: Ride) {
        context.insert(ride)
        try? context.save()
    }

    /// 时间区间与已有骑行重叠则视为重复，跳过。
    func insertIfNew(_ ride: Ride) {
        let existing = allRides()
        let overlaps = existing.contains { r in
            ride.startDate < r.endDate && r.startDate < ride.endDate
        }
        if !overlaps { insert(ride) }
    }

    func allRides() -> [Ride] {
        let descriptor = FetchDescriptor<Ride>(
            sortBy: [SortDescriptor(\.startDate, order: .reverse)]
        )
        return (try? context.fetch(descriptor)) ?? []
    }
}
```

- [ ] **Step 4: 跑测试确认通过**

```bash
xcodebuild test -project Bike.xcodeproj -scheme Bike \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:BikeTests/RideStoreTests
```
Expected: PASS

- [ ] **Step 5: 提交**

```bash
git add Bike/Store/RideStore.swift BikeTests/RideStoreTests.swift
git commit -m "feat(m1): RideStore CRUD + 时间重叠去重"
```

---

### Task 1.3: `CalorieCalculator`（纯逻辑 MET 公式）

**Files:**
- Create: `Bike/Detection/CalorieCalculator.swift`
- Create: `BikeTests/CalorieCalculatorTests.swift`

- [ ] **Step 1: 写失败测试 `BikeTests/CalorieCalculatorTests.swift`**

```swift
import Testing
@testable import Bike

@Test func caloriesWithoutSpeedUsesModerateMET() {
    // MET 6.8 × 70kg × 0.5h = 238
    let kcal = CalorieCalculator.calories(durationSeconds: 1800, avgSpeedKmh: nil, weightKg: 70)
    #expect(abs(kcal - 238) < 0.5)
}

@Test func caloriesWithModerateSpeed() {
    // 20 km/h -> MET 8.0；8.0 × 70 × 0.5 = 280
    let kcal = CalorieCalculator.calories(durationSeconds: 1800, avgSpeedKmh: 20, weightKg: 70)
    #expect(abs(kcal - 280) < 0.5)
}
```

- [ ] **Step 2: 跑测试确认失败**

```bash
xcodebuild test -project Bike.xcodeproj -scheme Bike \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:BikeTests/CalorieCalculatorTests
```
Expected: FAIL

- [ ] **Step 3: 写 `Bike/Detection/CalorieCalculator.swift`**

```swift
import Foundation

/// 基于 Compendium of Physical Activities 的骑行 MET 近似值。
enum CalorieCalculator {
    static func met(forSpeedKmh speed: Double?) -> Double {
        guard let s = speed else { return 6.8 }   // 无速度 -> 中等强度默认
        switch s {
        case ..<16:  return 4.0
        case 16..<19: return 6.8
        case 19..<22: return 8.0
        case 22..<25: return 10.0
        default:      return 12.0
        }
    }

    /// kcal = MET × 体重(kg) × 时长(小时)
    static func calories(durationSeconds: TimeInterval, avgSpeedKmh: Double?, weightKg: Double) -> Double {
        met(forSpeedKmh: avgSpeedKmh) * weightKg * (durationSeconds / 3600)
    }
}
```

- [ ] **Step 4: 跑测试确认通过**

```bash
xcodebuild test -project Bike.xcodeproj -scheme Bike \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:BikeTests/CalorieCalculatorTests
```
Expected: PASS

- [ ] **Step 5: 提交**

```bash
git add Bike/Detection/CalorieCalculator.swift BikeTests/CalorieCalculatorTests.swift
git commit -m "feat(m1): CalorieCalculator MET 公式"
```

---

### Task 1.4: `CyclingSegmentBuilder`（纯逻辑：活动样本 → 骑行段）

这是把 CoreMotion 数据变成骑行段的核心算法，独立成纯函数以便全覆盖测试（`CMMotionActivity` 无法在测试中构造）。

**Files:**
- Create: `Bike/Detection/ActivitySample.swift`
- Create: `Bike/Detection/MotionActivitySegment.swift`
- Create: `Bike/Detection/CyclingSegmentBuilder.swift`
- Create: `BikeTests/CyclingSegmentBuilderTests.swift`

- [ ] **Step 1: 写失败测试 `BikeTests/CyclingSegmentBuilderTests.swift`**

```swift
import Testing
import Foundation
@testable import Bike

private func t(_ s: TimeInterval) -> Date { Date(timeIntervalSince1970: s) }

@Test func buildsSingleCyclingSegmentMergingAdjacent() {
    // 两条相邻骑行样本应合并为一段，结束时间 = 下一条非骑行样本起点
    let samples = [
        ActivitySample(startDate: t(0),   isCycling: true,  confidence: 2),
        ActivitySample(startDate: t(120), isCycling: true,  confidence: 2),
        ActivitySample(startDate: t(300), isCycling: false, confidence: 2),
    ]
    let segs = CyclingSegmentBuilder.segments(from: samples, minDuration: 60)
    #expect(segs.count == 1)
    #expect(segs[0].startDate == t(0))
    #expect(segs[0].endDate == t(300))
}

@Test func filtersTooShortAndLowConfidence() {
    let samples = [
        ActivitySample(startDate: t(0),  isCycling: true,  confidence: 0), // 低置信 -> 丢
        ActivitySample(startDate: t(30), isCycling: false, confidence: 2),
        ActivitySample(startDate: t(40), isCycling: true,  confidence: 2), // 仅 20s < 60s -> 丢
        ActivitySample(startDate: t(60), isCycling: false, confidence: 2),
    ]
    let segs = CyclingSegmentBuilder.segments(from: samples, minDuration: 60)
    #expect(segs.isEmpty)
}
```

- [ ] **Step 2: 跑测试确认失败**

```bash
xcodebuild test -project Bike.xcodeproj -scheme Bike \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:BikeTests/CyclingSegmentBuilderTests
```
Expected: FAIL

- [ ] **Step 3: 写三个文件**

`Bike/Detection/ActivitySample.swift`：
```swift
import Foundation

/// 纯值类型，镜像 CMMotionActivity 中我们关心的字段（便于测试）。
struct ActivitySample: Equatable {
    let startDate: Date
    let isCycling: Bool
    let confidence: Int   // 0=low 1=medium 2=high
}
```

`Bike/Detection/MotionActivitySegment.swift`：
```swift
import Foundation

/// 一段连续骑行（基线层产物）。
struct MotionActivitySegment: Equatable {
    let startDate: Date
    let endDate: Date
    let confidence: Int
    var duration: TimeInterval { endDate.timeIntervalSince(startDate) }
}
```

`Bike/Detection/CyclingSegmentBuilder.swift`：
```swift
import Foundation

enum CyclingSegmentBuilder {
    /// 把按时间排序的活动样本压成骑行段。
    /// - 仅取 confidence >= medium(1) 的骑行样本
    /// - 相邻骑行样本合并；段结束时间 = 下一条样本起点
    /// - 丢弃短于 minDuration 的段
    static func segments(from samples: [ActivitySample], minDuration: TimeInterval) -> [MotionActivitySegment] {
        let sorted = samples.sorted { $0.startDate < $1.startDate }
        var result: [MotionActivitySegment] = []
        var segStart: Date?
        var segConfidence = 0

        func close(at end: Date) {
            if let start = segStart {
                let seg = MotionActivitySegment(startDate: start, endDate: end, confidence: segConfidence)
                if seg.duration >= minDuration { result.append(seg) }
            }
            segStart = nil
            segConfidence = 0
        }

        for i in sorted.indices {
            let s = sorted[i]
            let qualifies = s.isCycling && s.confidence >= 1
            if qualifies {
                if segStart == nil { segStart = s.startDate }
                segConfidence = max(segConfidence, s.confidence)
            } else {
                close(at: s.startDate)
            }
        }
        // 末尾仍开着的段：用最后一条样本时间收口（保守，可能略短）
        if let last = sorted.last { close(at: last.startDate) }
        return result
    }
}
```

- [ ] **Step 4: 跑测试确认通过**

```bash
xcodebuild test -project Bike.xcodeproj -scheme Bike \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:BikeTests/CyclingSegmentBuilderTests
```
Expected: PASS

- [ ] **Step 5: 提交**

```bash
git add Bike/Detection/ActivitySample.swift Bike/Detection/MotionActivitySegment.swift \
        Bike/Detection/CyclingSegmentBuilder.swift BikeTests/CyclingSegmentBuilderTests.swift
git commit -m "feat(m1): CyclingSegmentBuilder 活动样本->骑行段"
```

---

### Task 1.5: `RideReconciler`（纯逻辑：基线段 + GPS 骑行 合并去重）

**Files:**
- Create: `Bike/Detection/RideReconciler.swift`
- Create: `BikeTests/RideReconcilerTests.swift`

- [ ] **Step 1: 写失败测试 `BikeTests/RideReconcilerTests.swift`**

```swift
import Testing
import Foundation
@testable import Bike

private func t(_ s: TimeInterval) -> Date { Date(timeIntervalSince1970: s) }

@Test func reconcilerDropsMotionSegmentOverlappingGPSRide() {
    let gps = Ride(start: t(0), end: t(1200), source: .gpsTracked, confidence: 2)   // 10:00-10:20
    let segs = [
        MotionActivitySegment(startDate: t(300), endDate: t(1080), confidence: 2),  // 重叠 -> 丢
        MotionActivitySegment(startDate: t(5000), endDate: t(5600), confidence: 1), // 独立 -> 留
    ]
    let result = RideReconciler.reconcile(motionSegments: segs, gpsRides: [gps], weightKg: 70)
    #expect(result.count == 2)
    let motionOnly = result.filter { $0.source == .motionOnly }
    #expect(motionOnly.count == 1)
    #expect(motionOnly[0].startDate == t(5000))
    #expect(motionOnly[0].calories != nil)   // motionOnly 也估算卡路里（无速度，默认 MET）
}
```

- [ ] **Step 2: 跑测试确认失败**

```bash
xcodebuild test -project Bike.xcodeproj -scheme Bike \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:BikeTests/RideReconcilerTests
```
Expected: FAIL

- [ ] **Step 3: 写 `Bike/Detection/RideReconciler.swift`**

```swift
import Foundation

enum RideReconciler {
    /// 合并基线骑行段与 GPS 实采骑行：时间重叠则 GPS 胜出，其余基线段转为 motionOnly 骑行。
    static func reconcile(motionSegments: [MotionActivitySegment],
                          gpsRides: [Ride],
                          weightKg: Double) -> [Ride] {
        let motionOnly: [Ride] = motionSegments.compactMap { seg in
            let overlaps = gpsRides.contains { r in
                seg.startDate < r.endDate && r.startDate < seg.endDate
            }
            guard !overlaps else { return nil }
            let ride = Ride(start: seg.startDate, end: seg.endDate,
                            source: .motionOnly, confidence: seg.confidence)
            ride.calories = CalorieCalculator.calories(
                durationSeconds: seg.duration, avgSpeedKmh: nil, weightKg: weightKg)
            return ride
        }
        return (gpsRides + motionOnly).sorted { $0.startDate > $1.startDate }
    }
}
```

- [ ] **Step 4: 跑测试确认通过**

```bash
xcodebuild test -project Bike.xcodeproj -scheme Bike \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:BikeTests/RideReconcilerTests
```
Expected: PASS

- [ ] **Step 5: 提交**

```bash
git add Bike/Detection/RideReconciler.swift BikeTests/RideReconcilerTests.swift
git commit -m "feat(m1): RideReconciler 基线+GPS 合并去重"
```

---

### Task 1.6: `MotionHistoryProviding` 协议 + CoreMotion 实现

实现真机验证；测试只用 mock。把 `CMMotionActivity` → `ActivitySample` 的映射隔离在实现内，逻辑已由 Task 1.4 覆盖。

**Files:**
- Create: `Bike/Detection/MotionHistoryProviding.swift`
- Create: `Bike/Detection/MotionHistoryService.swift`

- [ ] **Step 1: 写 `Bike/Detection/MotionHistoryProviding.swift`**

```swift
import Foundation

protocol MotionHistoryProviding {
    /// 查询时间窗内的骑行段（已合并/过滤）。
    func cyclingSegments(from: Date, to: Date, minDuration: TimeInterval) async -> [MotionActivitySegment]
}
```

- [ ] **Step 2: 写 `Bike/Detection/MotionHistoryService.swift`**

```swift
import Foundation
import CoreMotion

final class MotionHistoryService: MotionHistoryProviding {
    private let manager = CMMotionActivityManager()

    static var isAvailable: Bool { CMMotionActivityManager.isActivityAvailable() }

    func cyclingSegments(from: Date, to: Date, minDuration: TimeInterval) async -> [MotionActivitySegment] {
        await withCheckedContinuation { continuation in
            manager.queryActivityStarting(from: from, to: to, to: .main) { activities, _ in
                let samples = (activities ?? []).map { a in
                    ActivitySample(
                        startDate: a.startDate,
                        isCycling: a.cycling,
                        confidence: a.confidence.rawValue
                    )
                }
                let segs = CyclingSegmentBuilder.segments(from: samples, minDuration: minDuration)
                continuation.resume(returning: segs)
            }
        }
    }
}
```

- [ ] **Step 3: 构建确认编译通过**

```bash
xcodebuild build -project Bike.xcodeproj -scheme Bike \
  -destination 'platform=iOS Simulator,name=iPhone 17'
```
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 4: 提交**

```bash
git add Bike/Detection/MotionHistoryProviding.swift Bike/Detection/MotionHistoryService.swift
git commit -m "feat(m1): MotionHistory 协议 + CMMotionActivityManager 实现"
```

> 真机验证（不在本地测试范围）：装到 iPhone，骑行几分钟后打开 app，确认 `cyclingSegments` 能回溯到该段。记录在 M1 收尾的设备验证清单。

---

### Task 1.7: `RideJournal` 协调器（拉历史 → 合并 → 入库）

**Files:**
- Create: `Bike/Detection/RideJournal.swift`
- Create: `BikeTests/RideJournalTests.swift`

- [ ] **Step 1: 写失败测试 `BikeTests/RideJournalTests.swift`**

```swift
import Testing
import Foundation
import SwiftData
@testable import Bike

private func t(_ s: TimeInterval) -> Date { Date(timeIntervalSince1970: s) }

private struct MockMotionProvider: MotionHistoryProviding {
    let segments: [MotionActivitySegment]
    func cyclingSegments(from: Date, to: Date, minDuration: TimeInterval) async -> [MotionActivitySegment] {
        segments
    }
}

@MainActor
@Test func journalImportsMotionSegmentsAsRides() async throws {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try ModelContainer(for: Ride.self, configurations: config)
    let store = RideStore(context: container.mainContext)
    let provider = MockMotionProvider(segments: [
        MotionActivitySegment(startDate: t(0), endDate: t(600), confidence: 2)
    ])
    let journal = RideJournal(store: store, motionProvider: provider, weightKg: 70)

    await journal.refresh(now: t(700))

    let rides = store.allRides()
    #expect(rides.count == 1)
    #expect(rides[0].source == .motionOnly)
    #expect(rides[0].calories != nil)

    // 再次 refresh 不应重复导入（时间重叠去重）
    await journal.refresh(now: t(700))
    #expect(store.allRides().count == 1)
}
```

- [ ] **Step 2: 跑测试确认失败**

```bash
xcodebuild test -project Bike.xcodeproj -scheme Bike \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:BikeTests/RideJournalTests
```
Expected: FAIL

- [ ] **Step 3: 写 `Bike/Detection/RideJournal.swift`**

```swift
import Foundation

@MainActor
final class RideJournal {
    private let store: RideStore
    private let motionProvider: MotionHistoryProviding
    private let weightKg: Double
    private let lookback: TimeInterval = 7 * 24 * 3600   // 回溯 7 天
    private let minRideDuration: TimeInterval = 90       // 见 spec：捕捉短途

    init(store: RideStore, motionProvider: MotionHistoryProviding, weightKg: Double) {
        self.store = store
        self.motionProvider = motionProvider
        self.weightKg = weightKg
    }

    /// 拉运动历史 -> 与已存骑行合并去重 -> 入库。
    func refresh(now: Date = Date()) async {
        let segs = await motionProvider.cyclingSegments(
            from: now.addingTimeInterval(-lookback), to: now, minDuration: minRideDuration)
        // M1 暂无 GPS 骑行；reconcile 仅把基线段转 motionOnly 并估卡路里
        let candidates = RideReconciler.reconcile(motionSegments: segs, gpsRides: [], weightKg: weightKg)
        for ride in candidates { store.insertIfNew(ride) }
    }
}
```

- [ ] **Step 4: 跑测试确认通过**

```bash
xcodebuild test -project Bike.xcodeproj -scheme Bike \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:BikeTests/RideJournalTests
```
Expected: PASS

- [ ] **Step 5: 提交**

```bash
git add Bike/Detection/RideJournal.swift BikeTests/RideJournalTests.swift
git commit -m "feat(m1): RideJournal 协调器（拉历史->合并->入库）"
```

---

### Task 1.8: `RideListViewModel` + 时间线 UI + 接线

**Files:**
- Create: `Bike/UI/RideListViewModel.swift`
- Create: `BikeTests/RideListViewModelTests.swift`
- Create: `Bike/UI/RideRowView.swift`
- Create: `Bike/UI/RideTimelineView.swift`
- Modify: `Bike/App/BikeApp.swift`
- Modify: `Bike/App/RootView.swift`

- [ ] **Step 1: 写失败测试 `BikeTests/RideListViewModelTests.swift`**

```swift
import Testing
import Foundation
@testable import Bike

private func t(_ s: TimeInterval) -> Date { Date(timeIntervalSince1970: s) }

@Test func viewModelFormatsDurationAndDistance() {
    let ride = Ride(start: t(0), end: t(754), source: .gpsTracked, confidence: 2,
                    distanceMeters: 3200)
    let row = RideListViewModel.row(for: ride)
    #expect(row.durationText == "12 分 34 秒")
    #expect(row.distanceText == "3.2 km")
}

@Test func viewModelHidesDistanceWhenMotionOnly() {
    let ride = Ride(start: t(0), end: t(600), source: .motionOnly, confidence: 2)
    let row = RideListViewModel.row(for: ride)
    #expect(row.distanceText == nil)
}
```

- [ ] **Step 2: 跑测试确认失败**

```bash
xcodebuild test -project Bike.xcodeproj -scheme Bike \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:BikeTests/RideListViewModelTests
```
Expected: FAIL

- [ ] **Step 3: 写 `Bike/UI/RideListViewModel.swift`**

```swift
import Foundation

struct RideRowModel: Identifiable {
    let id: UUID
    let dateText: String
    let durationText: String
    let distanceText: String?
    let caloriesText: String?
}

enum RideListViewModel {
    static func row(for ride: Ride) -> RideRowModel {
        let mins = Int(ride.duration) / 60
        let secs = Int(ride.duration) % 60
        let duration = "\(mins) 分 \(secs) 秒"

        var distance: String?
        if let m = ride.distanceMeters {
            distance = String(format: "%.1f km", m / 1000)
        }
        var calories: String?
        if let c = ride.calories {
            calories = "\(Int(c.rounded())) 千卡"
        }
        let df = DateFormatter()
        df.dateFormat = "M月d日 HH:mm"
        return RideRowModel(id: ride.id, dateText: df.string(from: ride.startDate),
                            durationText: duration, distanceText: distance, caloriesText: calories)
    }
}
```

- [ ] **Step 4: 跑测试确认通过**

```bash
xcodebuild test -project Bike.xcodeproj -scheme Bike \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:BikeTests/RideListViewModelTests
```
Expected: PASS

- [ ] **Step 5: 写 `Bike/UI/RideRowView.swift`**

```swift
import SwiftUI

struct RideRowView: View {
    let model: RideRowModel
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(model.dateText).font(.headline)
            HStack(spacing: 12) {
                Label(model.durationText, systemImage: "clock")
                if let d = model.distanceText { Label(d, systemImage: "ruler") }
                if let c = model.caloriesText { Label(c, systemImage: "flame") }
            }
            .font(.subheadline).foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}
```

- [ ] **Step 6: 写 `Bike/UI/RideTimelineView.swift`**

```swift
import SwiftUI
import SwiftData

struct RideTimelineView: View {
    @Query(sort: \Ride.startDate, order: .reverse) private var rides: [Ride]

    var body: some View {
        NavigationStack {
            Group {
                if rides.isEmpty {
                    ContentUnavailableView("还没有骑行记录",
                        systemImage: "bicycle",
                        description: Text("骑车出门转一圈，回来这里就会自动出现。"))
                } else {
                    List(rides) { ride in
                        RideRowView(model: RideListViewModel.row(for: ride))
                    }
                }
            }
            .navigationTitle("骑行")
        }
    }
}
```

- [ ] **Step 7: 改 `Bike/App/RootView.swift`**

```swift
import SwiftUI

struct RootView: View {
    var body: some View {
        RideTimelineView()
    }
}
```

- [ ] **Step 8: 改 `Bike/App/BikeApp.swift`（注入 ModelContainer + 启动刷新）**

```swift
import SwiftUI
import SwiftData

@main
struct BikeApp: App {
    let container: ModelContainer

    init() {
        container = try! ModelContainer(for: Ride.self)
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .task { await refreshJournal() }
        }
        .modelContainer(container)
    }

    @MainActor
    private func refreshJournal() async {
        guard MotionHistoryService.isAvailable else { return }
        let store = RideStore(context: container.mainContext)
        let journal = RideJournal(store: store,
                                  motionProvider: MotionHistoryService(),
                                  weightKg: 70)   // M3 起从 HealthKit 读真实体重
        await journal.refresh()
    }
}
```

- [ ] **Step 9: 构建 + 全量测试**

```bash
xcodebuild test -project Bike.xcodeproj -scheme Bike \
  -destination 'platform=iOS Simulator,name=iPhone 17'
```
Expected: `** TEST SUCCEEDED **`（全部测试通过）

- [ ] **Step 10: 模拟器启动冒烟（人工看一眼空态）**

```bash
xcrun simctl boot "iPhone 17" 2>/dev/null; \
xcodebuild build -project Bike.xcodeproj -scheme Bike \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -derivedDataPath build
xcrun simctl install booted "$(find build -name 'Bike.app' -maxdepth 4 | head -1)"
xcrun simctl launch booted com.bochen.bike
```
Expected: app 启动，显示「还没有骑行记录」空态（模拟器无运动历史，符合预期）。

- [ ] **Step 11: 提交**

```bash
git add Bike/UI BikeTests/RideListViewModelTests.swift Bike/App
git commit -m "feat(m1): 时间线 UI + ViewModel + 启动刷新接线"
```

---

### M1 收尾：真机设备验证清单（不可在模拟器完成）

- [ ] 装到真 iPhone（需在 project.yml 填 `DEVELOPMENT_TEAM` 并连接设备签名）
- [ ] 首次启动弹出运动权限，允许
- [ ] 骑车 5–10 分钟（或步行/开车做对照）
- [ ] 回来打开 app，确认骑行段出现在时间线、时长合理
- [ ] 确认非骑行活动（走/开车）未被误记

---

## M2–M5 路线图（执行到此各自展开为完整任务计划）

### M2 — GPS 增强
- `LocationWakeService`：`startMonitoringSignificantLocationChanges` 后台唤醒
- `LiveRideTracker`：确认骑行后启动 `CLLocationManager` 全功率 GPS，采点直到骑行停止（去抖 ~2 分钟）
- 距离（轨迹累加）、均速、卡路里（用真实速度选 MET）、`RoutePoint` 路线落库
- `RideReconciler` 接入真实 `gpsRides`
- `BackgroundCoordinator`：`BGTaskScheduler` 定期回溯对账
- 权限：`NSLocationAlwaysAndWhenInUseUsageDescription` + Background Modes `location`
- 详情页用 `MapKit` 画轨迹

### M3 — HealthKit + 通知
- `HealthKitService`：`HKWorkoutBuilder(.cycling)` + `HKWorkoutRouteBuilder` 写回（含路线），回填 `healthKitWorkoutUUID`
- 读 `HKQuantityType.bodyMass` 作为真实体重（替换 70kg 默认）
- 设置项「写回健康」开关，默认开
- `NotificationService`：骑行结束本地推送
- 权限：`NSHealthUpdateUsageDescription` / `NSHealthShareUsageDescription`
- ⚠️ 实测确认绿环（Exercise）是否计入

### M4 — Apple Watch
- watchOS target；`HKWorkoutSession` + `HKLiveWorkoutBuilder` 采心率
- `WatchSessionManager`（双端 `WatchConnectivity`）：iPhone 检测到骑行 → 触发手表采心率
- complication：今日骑行时长
- ⚠️ 验证后台静默启动可行性（spec §10 头号风险），不行则降级 v2

### M5 — 统计趋势 UI
- 日/周汇总（总时长/距离/次数/卡路里）
- 趋势图（Swift Charts）
- 骑行详情页完善

---

## Self-Review

- **Spec coverage**：M1 覆盖 spec 的基线检测/存储/去重/卡路里/极简 UI；GPS(§7 实时)、HealthKit(§9)、Watch(§10)、统计 分别由 M2/M3/M4/M5 覆盖；权限(§8)随各里程碑引入。无遗漏。
- **Placeholder scan**：M0–M1 每步含完整代码与命令，无 TBD/TODO；M2–M5 明确标注为路线图、执行时展开（非占位符代码）。
- **Type consistency**：`Ride` 构造器、`RideSource`、`MotionActivitySegment`、`ActivitySample`、`MotionHistoryProviding.cyclingSegments(from:to:minDuration:)`、`RideReconciler.reconcile(motionSegments:gpsRides:weightKg:)`、`RideStore.insertIfNew`、`CalorieCalculator.calories(durationSeconds:avgSpeedKmh:weightKg:)`、`RideListViewModel.row(for:)` 跨任务签名一致。
