# 被动骑行日志 — M1：领域逻辑包 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 把骑行检测的纯逻辑（时段合并、GPS 距离/速度、误判过滤、卡路里估算、多源对账合并）做成一个无 UI、无传感器依赖的 SwiftPM 包，用 `swift test` 完整 TDD，作为整个 app 的可测试地基。

**Architecture:** 一个纯 Foundation 的 Swift Package `CyclingDomain`，放在 `Packages/CyclingDomain/`。所有类型用普通 `struct`/`enum`（不依赖 CoreMotion/CoreLocation/SwiftData），便于在 macOS 宿主上跑 `swift test`。后续 M2 的 iOS app 工程以「本地包依赖」方式引用它，传感器层只负责把原始数据转成本包的输入类型。

**Tech Stack:** Swift 6 / SwiftPM / XCTest。无需完整 Xcode（Command Line Tools 即可）。

## 前置条件 (Prerequisites)

- 已确认：`xcodegen` 2.42、`swift` 6.4 可用。
- ⚠️ 本机仅 Command Line Tools，**无完整 Xcode** → 本 M1 不依赖 Xcode，可直接执行。M2 起需先 `sudo xcode-select -s /Applications/Xcode.app/Contents/Developer`。
- 所有命令在仓库根 `/Users/sirchen/bike` 下执行；包路径 `Packages/CyclingDomain`。

## 里程碑路线图（本计划只覆盖 M1）

| 里程碑 | 内容 | 依赖 | 计划文件 |
|--------|------|------|---------|
| **M1** | 领域逻辑包（本文件） | 仅 CLT | 本文件 |
| M2 | XcodeGen 工程 + SwiftData + 时间线 UI | Xcode | 待写 |
| M3 | CoreMotion 基线 + 定位唤醒 + LiveRideTracker | Xcode+真机 | 待写 |
| M4 | HealthKit 写回 + 通知 | Xcode+真机 | 待写 |
| M5 | 完整 UI（详情/地图/统计/设置） | Xcode | 待写 |
| M6 | Apple Watch（心率/complication/WatchConnectivity） | Xcode+真机 | 待写 |

## 文件结构（M1 产出）

```
Packages/CyclingDomain/
  Package.swift
  Sources/CyclingDomain/
    RideTypes.swift          # RideSource, MotionSegment, GPSSample, TrackedRide, Ride
    SegmentMerging.swift     # 相邻时段合并 + 最小时长过滤
    GPSMetrics.swift         # haversine 距离、均速
    SpeedFilter.swift        # 骑行均速合理性
    CalorieEstimator.swift   # 基于速度的 MET 卡路里
    RideReconciler.swift     # 多源对账：合并/去重/分类来源
  Tests/CyclingDomainTests/
    SegmentMergingTests.swift
    GPSMetricsTests.swift
    SpeedFilterTests.swift
    CalorieEstimatorTests.swift
    RideReconcilerTests.swift
```

每个文件单一职责。`RideTypes.swift` 是被所有逻辑文件共享的纯数据定义。

---

## Task 0: SwiftPM 包骨架

**Files:**
- Create: `Packages/CyclingDomain/Package.swift`
- Create: `Packages/CyclingDomain/Sources/CyclingDomain/RideTypes.swift`

- [ ] **Step 1: 写 Package.swift**

```swift
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CyclingDomain",
    platforms: [.macOS(.v13), .iOS(.v17), .watchOS(.v10)],
    products: [
        .library(name: "CyclingDomain", targets: ["CyclingDomain"]),
    ],
    targets: [
        .target(name: "CyclingDomain"),
        .testTarget(name: "CyclingDomainTests", dependencies: ["CyclingDomain"]),
    ]
)
```

- [ ] **Step 2: 写最小源文件（让包能编译）** `Sources/CyclingDomain/RideTypes.swift`

```swift
import Foundation

/// 一次骑行记录的数据来源。
public enum RideSource: String, Sendable, Codable {
    case motionOnly   // 仅 CoreMotion 运动历史（有时长，无路线）
    case gpsTracked   // 仅 GPS 实采（理论边缘情况）
    case merged       // 运动历史 + GPS 实采都覆盖（最完整）
}

/// CoreMotion 回溯查询得到的一个骑行时段（基线层输入）。
public struct MotionSegment: Equatable, Sendable {
    public let start: Date
    public let end: Date
    /// CoreMotion 置信度：0=low, 1=medium, 2=high
    public let confidence: Int
    public init(start: Date, end: Date, confidence: Int) {
        self.start = start
        self.end = end
        self.confidence = confidence
    }
    public var duration: TimeInterval { end.timeIntervalSince(start) }
}

/// 一个 GPS 采样点（增强层输入）。经纬度用普通 Double，保持包无 CoreLocation 依赖。
public struct GPSSample: Equatable, Sendable {
    public let timestamp: Date
    public let latitude: Double
    public let longitude: Double
    /// 瞬时速度 m/s，负值表示无效。
    public let speedMps: Double
    public init(timestamp: Date, latitude: Double, longitude: Double, speedMps: Double) {
        self.timestamp = timestamp
        self.latitude = latitude
        self.longitude = longitude
        self.speedMps = speedMps
    }
}

/// LiveRideTracker 实采到的一次骑行（增强层输出，进对账器）。
public struct TrackedRide: Equatable, Sendable {
    public let start: Date
    public let end: Date
    public let samples: [GPSSample]
    public init(start: Date, end: Date, samples: [GPSSample]) {
        self.start = start
        self.end = end
        self.samples = samples
    }
}

/// 对账后的最终骑行记录（领域层输出；M2 会映射成 SwiftData @Model）。
public struct Ride: Equatable, Sendable {
    public let start: Date
    public let end: Date
    public let source: RideSource
    public let distanceMeters: Double?
    public let avgSpeedMps: Double?
    public let calories: Double?
    public let confidence: Int
    public init(start: Date, end: Date, source: RideSource,
                distanceMeters: Double?, avgSpeedMps: Double?,
                calories: Double?, confidence: Int) {
        self.start = start
        self.end = end
        self.source = source
        self.distanceMeters = distanceMeters
        self.avgSpeedMps = avgSpeedMps
        self.calories = calories
        self.confidence = confidence
    }
    public var duration: TimeInterval { end.timeIntervalSince(start) }
}
```

- [ ] **Step 3: 编译验证**

Run: `swift build --package-path Packages/CyclingDomain`
Expected: `Build complete!`（无错误）

- [ ] **Step 4: 提交**

```bash
git add Packages/CyclingDomain
git commit -m "feat(domain): CyclingDomain 包骨架 + 核心数据类型"
```

---

## Task 1: 时段合并与最小时长过滤

把 CoreMotion 返回的细碎相邻骑行时段合并，并丢弃过短噪声。最小骑行时长**默认 90 秒**（刻意调低以捕捉短途）。

**Files:**
- Create: `Packages/CyclingDomain/Sources/CyclingDomain/SegmentMerging.swift`
- Test: `Packages/CyclingDomain/Tests/CyclingDomainTests/SegmentMergingTests.swift`

- [ ] **Step 1: 写失败测试**

```swift
import XCTest
@testable import CyclingDomain

final class SegmentMergingTests: XCTestCase {
    private func d(_ s: TimeInterval) -> Date { Date(timeIntervalSince1970: s) }

    func test_mergesSegmentsWithinGap() {
        let segs = [
            MotionSegment(start: d(0),   end: d(120), confidence: 2),
            MotionSegment(start: d(140), end: d(300), confidence: 2), // 20s 间隔 < 60s → 合并
        ]
        let merged = mergeCyclingSegments(segs, maxGap: 60, minDuration: 90)
        XCTAssertEqual(merged.count, 1)
        XCTAssertEqual(merged[0].start, d(0))
        XCTAssertEqual(merged[0].end, d(300))
    }

    func test_keepsSegmentsApartBeyondGap() {
        let segs = [
            MotionSegment(start: d(0),    end: d(120),  confidence: 2),
            MotionSegment(start: d(1000), end: d(1200), confidence: 2), // 间隔远 → 不合并
        ]
        let merged = mergeCyclingSegments(segs, maxGap: 60, minDuration: 90)
        XCTAssertEqual(merged.count, 2)
    }

    func test_dropsTooShortSegments() {
        let segs = [
            MotionSegment(start: d(0), end: d(30), confidence: 2), // 30s < 90s → 丢
        ]
        let merged = mergeCyclingSegments(segs, maxGap: 60, minDuration: 90)
        XCTAssertTrue(merged.isEmpty)
    }

    func test_mergedConfidenceIsMax() {
        let segs = [
            MotionSegment(start: d(0),   end: d(120), confidence: 1),
            MotionSegment(start: d(130), end: d(300), confidence: 2),
        ]
        let merged = mergeCyclingSegments(segs, maxGap: 60, minDuration: 90)
        XCTAssertEqual(merged[0].confidence, 2)
    }
}
```

- [ ] **Step 2: 跑测试确认失败**

Run: `swift test --package-path Packages/CyclingDomain --filter SegmentMergingTests`
Expected: 编译失败 `cannot find 'mergeCyclingSegments' in scope`

- [ ] **Step 3: 写实现** `Sources/CyclingDomain/SegmentMerging.swift`

```swift
import Foundation

/// 合并时间上相邻（间隔 <= maxGap）的骑行时段，并丢弃合并后短于 minDuration 的结果。
/// - 输入无需有序；内部按 start 排序。
/// - 合并后时段的置信度取参与合并各段的最大值。
public func mergeCyclingSegments(
    _ segments: [MotionSegment],
    maxGap: TimeInterval,
    minDuration: TimeInterval
) -> [MotionSegment] {
    let sorted = segments.sorted { $0.start < $1.start }
    var result: [MotionSegment] = []
    for seg in sorted {
        if let last = result.last, seg.start.timeIntervalSince(last.end) <= maxGap {
            result[result.count - 1] = MotionSegment(
                start: last.start,
                end: max(last.end, seg.end),
                confidence: max(last.confidence, seg.confidence)
            )
        } else {
            result.append(seg)
        }
    }
    return result.filter { $0.duration >= minDuration }
}
```

- [ ] **Step 4: 跑测试确认通过**

Run: `swift test --package-path Packages/CyclingDomain --filter SegmentMergingTests`
Expected: 全部 PASS

- [ ] **Step 5: 提交**

```bash
git add Packages/CyclingDomain
git commit -m "feat(domain): 骑行时段合并与最小时长过滤"
```

---

## Task 2: GPS 距离与均速

从 GPS 采样点用 haversine 算累计距离，并由距离/时长算均速。

**Files:**
- Create: `Packages/CyclingDomain/Sources/CyclingDomain/GPSMetrics.swift`
- Test: `Packages/CyclingDomain/Tests/CyclingDomainTests/GPSMetricsTests.swift`

- [ ] **Step 1: 写失败测试**

```swift
import XCTest
@testable import CyclingDomain

final class GPSMetricsTests: XCTestCase {
    private func d(_ s: TimeInterval) -> Date { Date(timeIntervalSince1970: s) }

    func test_distanceBetweenTwoPoints() {
        // 纬度相差 0.001 度 ≈ 111.2 m
        let samples = [
            GPSSample(timestamp: d(0), latitude: 0.000, longitude: 0, speedMps: 5),
            GPSSample(timestamp: d(10), latitude: 0.001, longitude: 0, speedMps: 5),
        ]
        let dist = totalDistanceMeters(samples)
        XCTAssertEqual(dist, 111.2, accuracy: 1.0)
    }

    func test_distanceWithFewerThanTwoSamplesIsZero() {
        XCTAssertEqual(totalDistanceMeters([]), 0)
        XCTAssertEqual(totalDistanceMeters([
            GPSSample(timestamp: d(0), latitude: 1, longitude: 1, speedMps: 5)
        ]), 0)
    }

    func test_averageSpeed() {
        // 1000 m / 100 s = 10 m/s
        XCTAssertEqual(averageSpeedMps(distanceMeters: 1000, duration: 100), 10, accuracy: 0.0001)
    }

    func test_averageSpeedZeroDurationIsZero() {
        XCTAssertEqual(averageSpeedMps(distanceMeters: 1000, duration: 0), 0)
    }
}
```

- [ ] **Step 2: 跑测试确认失败**

Run: `swift test --package-path Packages/CyclingDomain --filter GPSMetricsTests`
Expected: 编译失败 `cannot find 'totalDistanceMeters' in scope`

- [ ] **Step 3: 写实现** `Sources/CyclingDomain/GPSMetrics.swift`

```swift
import Foundation

/// 两点间 haversine 距离（米）。
public func haversineMeters(lat1: Double, lon1: Double, lat2: Double, lon2: Double) -> Double {
    let earthRadius = 6_371_000.0
    let dLat = (lat2 - lat1) * .pi / 180
    let dLon = (lon2 - lon1) * .pi / 180
    let a = sin(dLat / 2) * sin(dLat / 2)
        + cos(lat1 * .pi / 180) * cos(lat2 * .pi / 180)
        * sin(dLon / 2) * sin(dLon / 2)
    let c = 2 * atan2(sqrt(a), sqrt(1 - a))
    return earthRadius * c
}

/// 沿采样点累计的总距离（米）。少于 2 点返回 0。
public func totalDistanceMeters(_ samples: [GPSSample]) -> Double {
    guard samples.count >= 2 else { return 0 }
    var total = 0.0
    for i in 1..<samples.count {
        total += haversineMeters(
            lat1: samples[i - 1].latitude, lon1: samples[i - 1].longitude,
            lat2: samples[i].latitude,     lon2: samples[i].longitude
        )
    }
    return total
}

/// 均速 m/s。时长 <= 0 返回 0。
public func averageSpeedMps(distanceMeters: Double, duration: TimeInterval) -> Double {
    guard duration > 0 else { return 0 }
    return distanceMeters / duration
}
```

- [ ] **Step 4: 跑测试确认通过**

Run: `swift test --package-path Packages/CyclingDomain --filter GPSMetricsTests`
Expected: 全部 PASS

- [ ] **Step 5: 提交**

```bash
git add Packages/CyclingDomain
git commit -m "feat(domain): GPS haversine 距离与均速"
```

---

## Task 3: 骑行均速合理性过滤

排除明显不是骑行的均速（电动车/汽车太快、步行太慢）。骑行区间约 8–35 km/h = 2.22–9.72 m/s。

**Files:**
- Create: `Packages/CyclingDomain/Sources/CyclingDomain/SpeedFilter.swift`
- Test: `Packages/CyclingDomain/Tests/CyclingDomainTests/SpeedFilterTests.swift`

- [ ] **Step 1: 写失败测试**

```swift
import XCTest
@testable import CyclingDomain

final class SpeedFilterTests: XCTestCase {
    func test_typicalCyclingSpeedIsPlausible() {
        XCTAssertTrue(isPlausibleCyclingSpeed(mps: 20 / 3.6)) // 20 km/h
    }
    func test_carSpeedIsNotPlausible() {
        XCTAssertFalse(isPlausibleCyclingSpeed(mps: 80 / 3.6)) // 80 km/h
    }
    func test_walkingSpeedIsNotPlausible() {
        XCTAssertFalse(isPlausibleCyclingSpeed(mps: 4 / 3.6)) // 4 km/h
    }
    func test_boundariesInclusive() {
        XCTAssertTrue(isPlausibleCyclingSpeed(mps: 8 / 3.6))
        XCTAssertTrue(isPlausibleCyclingSpeed(mps: 35 / 3.6))
    }
}
```

- [ ] **Step 2: 跑测试确认失败**

Run: `swift test --package-path Packages/CyclingDomain --filter SpeedFilterTests`
Expected: 编译失败 `cannot find 'isPlausibleCyclingSpeed' in scope`

- [ ] **Step 3: 写实现** `Sources/CyclingDomain/SpeedFilter.swift`

```swift
import Foundation

/// 均速是否落在合理骑行区间（约 8–35 km/h，边界含）。
public func isPlausibleCyclingSpeed(
    mps: Double,
    minKmh: Double = 8,
    maxKmh: Double = 35
) -> Bool {
    let kmh = mps * 3.6
    return kmh >= minKmh && kmh <= maxKmh
}
```

- [ ] **Step 4: 跑测试确认通过**

Run: `swift test --package-path Packages/CyclingDomain --filter SpeedFilterTests`
Expected: 全部 PASS

- [ ] **Step 5: 提交**

```bash
git add Packages/CyclingDomain
git commit -m "feat(domain): 骑行均速合理性过滤"
```

---

## Task 4: 卡路里估算（基于速度的 MET）

v1 用速度分档的 MET 公式：`kcal = METs × 体重kg × 小时`。默认体重 70kg。心率修正留 M4。

**Files:**
- Create: `Packages/CyclingDomain/Sources/CyclingDomain/CalorieEstimator.swift`
- Test: `Packages/CyclingDomain/Tests/CyclingDomainTests/CalorieEstimatorTests.swift`

- [ ] **Step 1: 写失败测试**

```swift
import XCTest
@testable import CyclingDomain

final class CalorieEstimatorTests: XCTestCase {
    func test_metsBuckets() {
        XCTAssertEqual(cyclingMETs(avgSpeedMps: 14 / 3.6), 4.0)  // <16
        XCTAssertEqual(cyclingMETs(avgSpeedMps: 18 / 3.6), 6.0)  // 16–19
        XCTAssertEqual(cyclingMETs(avgSpeedMps: 21 / 3.6), 8.0)  // 19–22
        XCTAssertEqual(cyclingMETs(avgSpeedMps: 24 / 3.6), 10.0) // 22–25
        XCTAssertEqual(cyclingMETs(avgSpeedMps: 30 / 3.6), 12.0) // >=25
    }

    func test_caloriesKnownCase() {
        // 20 km/h(=8 METs 档? 不，20 在 19–22 → 8 METs) × 70kg × 1h = 560
        let kcal = estimateCalories(avgSpeedMps: 20 / 3.6, duration: 3600, weightKg: 70)
        XCTAssertEqual(kcal, 560, accuracy: 0.001)
    }

    func test_caloriesScalesWithDuration() {
        let half = estimateCalories(avgSpeedMps: 20 / 3.6, duration: 1800, weightKg: 70)
        XCTAssertEqual(half, 280, accuracy: 0.001)
    }
}
```

- [ ] **Step 2: 跑测试确认失败**

Run: `swift test --package-path Packages/CyclingDomain --filter CalorieEstimatorTests`
Expected: 编译失败 `cannot find 'cyclingMETs' in scope`

- [ ] **Step 3: 写实现** `Sources/CyclingDomain/CalorieEstimator.swift`

```swift
import Foundation

/// 骑行 MET 值，按均速分档（Compendium of Physical Activities 近似）。
public func cyclingMETs(avgSpeedMps: Double) -> Double {
    let kmh = avgSpeedMps * 3.6
    switch kmh {
    case ..<16: return 4.0
    case ..<19: return 6.0
    case ..<22: return 8.0
    case ..<25: return 10.0
    default:    return 12.0
    }
}

/// 估算消耗卡路里：kcal = METs × 体重kg × 小时。
public func estimateCalories(
    avgSpeedMps: Double,
    duration: TimeInterval,
    weightKg: Double = 70
) -> Double {
    let hours = duration / 3600
    return cyclingMETs(avgSpeedMps: avgSpeedMps) * weightKg * hours
}
```

- [ ] **Step 4: 跑测试确认通过**

Run: `swift test --package-path Packages/CyclingDomain --filter CalorieEstimatorTests`
Expected: 全部 PASS

- [ ] **Step 5: 提交**

```bash
git add Packages/CyclingDomain
git commit -m "feat(domain): 基于速度 MET 的卡路里估算"
```

---

## Task 5: 多源对账合并 RideReconciler

把基线（已合并的 MotionSegment）与实采（TrackedRide）对账成最终 `Ride` 列表：
- 时间重叠的 motion 段与 tracked → 一条 `.merged`（带 GPS 距离/速度/卡路里）
- 无 motion 覆盖的 tracked → `.gpsTracked`
- 无 tracked 覆盖的 motion 段 → `.motionOnly`（仅时长，距离/速度/卡路里为 nil）
- tracked 的均速若不合理（见 Task 3）则丢弃该 tracked

**Files:**
- Create: `Packages/CyclingDomain/Sources/CyclingDomain/RideReconciler.swift`
- Test: `Packages/CyclingDomain/Tests/CyclingDomainTests/RideReconcilerTests.swift`

- [ ] **Step 1: 写失败测试**

```swift
import XCTest
@testable import CyclingDomain

final class RideReconcilerTests: XCTestCase {
    private func d(_ s: TimeInterval) -> Date { Date(timeIntervalSince1970: s) }

    /// 构造一条均速约 20km/h、时长 t 秒的 tracked（两点拉开足够距离）。
    private func tracked(start: TimeInterval, durationSec: TimeInterval) -> TrackedRide {
        // 20 km/h ≈ 5.556 m/s；距离 = 5.556 * durationSec
        // 用纬度位移制造距离：1 度纬度 ≈ 111_320 m
        let meters = 5.556 * durationSec
        let dLat = meters / 111_320.0
        return TrackedRide(
            start: d(start), end: d(start + durationSec),
            samples: [
                GPSSample(timestamp: d(start), latitude: 0, longitude: 0, speedMps: 5.556),
                GPSSample(timestamp: d(start + durationSec), latitude: dLat, longitude: 0, speedMps: 5.556),
            ]
        )
    }

    func test_overlappingMotionAndTrackedBecomesMerged() {
        let motion = [MotionSegment(start: d(0), end: d(600), confidence: 2)]
        let rides = RideReconciler.reconcile(motionSegments: motion, trackedRides: [tracked(start: 60, durationSec: 480)])
        XCTAssertEqual(rides.count, 1)
        XCTAssertEqual(rides[0].source, .merged)
        XCTAssertNotNil(rides[0].distanceMeters)
        XCTAssertNotNil(rides[0].calories)
    }

    func test_motionWithoutTrackedIsMotionOnly() {
        let motion = [MotionSegment(start: d(0), end: d(300), confidence: 1)]
        let rides = RideReconciler.reconcile(motionSegments: motion, trackedRides: [])
        XCTAssertEqual(rides.count, 1)
        XCTAssertEqual(rides[0].source, .motionOnly)
        XCTAssertNil(rides[0].distanceMeters)
        XCTAssertNil(rides[0].calories)
        XCTAssertEqual(rides[0].confidence, 1)
    }

    func test_trackedWithoutMotionIsGpsTracked() {
        let rides = RideReconciler.reconcile(motionSegments: [], trackedRides: [tracked(start: 0, durationSec: 300)])
        XCTAssertEqual(rides.count, 1)
        XCTAssertEqual(rides[0].source, .gpsTracked)
        XCTAssertNotNil(rides[0].distanceMeters)
    }

    func test_implausibleSpeedTrackedIsDropped() {
        // 制造一个超快 tracked：120 km/h
        let fast = TrackedRide(
            start: d(0), end: d(100),
            samples: [
                GPSSample(timestamp: d(0), latitude: 0, longitude: 0, speedMps: 33),
                GPSSample(timestamp: d(100), latitude: (33.3 * 100) / 111_320.0, longitude: 0, speedMps: 33),
            ]
        )
        let rides = RideReconciler.reconcile(motionSegments: [], trackedRides: [fast])
        XCTAssertTrue(rides.isEmpty)
    }

    func test_resultSortedByStart() {
        let motion = [
            MotionSegment(start: d(1000), end: d(1300), confidence: 1),
            MotionSegment(start: d(0),    end: d(300),  confidence: 1),
        ]
        let rides = RideReconciler.reconcile(motionSegments: motion, trackedRides: [])
        XCTAssertEqual(rides.map { $0.start }, [d(0), d(1000)])
    }
}
```

- [ ] **Step 2: 跑测试确认失败**

Run: `swift test --package-path Packages/CyclingDomain --filter RideReconcilerTests`
Expected: 编译失败 `cannot find 'RideReconciler' in scope`

- [ ] **Step 3: 写实现** `Sources/CyclingDomain/RideReconciler.swift`

```swift
import Foundation

public enum RideReconciler {

    /// 两个时间区间是否重叠。
    private static func overlaps(_ aStart: Date, _ aEnd: Date, _ bStart: Date, _ bEnd: Date) -> Bool {
        aStart < bEnd && bStart < aEnd
    }

    /// 由一条 TrackedRide 计算出带 GPS 指标的 Ride；均速不合理返回 nil（丢弃）。
    private static func rideFromTracked(
        _ tracked: TrackedRide,
        source: RideSource,
        confidence: Int
    ) -> Ride? {
        let distance = totalDistanceMeters(tracked.samples)
        let duration = tracked.end.timeIntervalSince(tracked.start)
        let speed = averageSpeedMps(distanceMeters: distance, duration: duration)
        guard isPlausibleCyclingSpeed(mps: speed) else { return nil }
        let kcal = estimateCalories(avgSpeedMps: speed, duration: duration)
        return Ride(
            start: tracked.start, end: tracked.end, source: source,
            distanceMeters: distance, avgSpeedMps: speed, calories: kcal,
            confidence: confidence
        )
    }

    /// 对账合并基线与实采。
    public static func reconcile(
        motionSegments: [MotionSegment],
        trackedRides: [TrackedRide]
    ) -> [Ride] {
        var rides: [Ride] = []

        // 1) 每条 tracked：有重叠 motion 段 → merged，否则 gpsTracked；均速不合理则丢弃。
        for tracked in trackedRides {
            let overlappingConfidences = motionSegments
                .filter { overlaps(tracked.start, tracked.end, $0.start, $0.end) }
                .map { $0.confidence }
            let source: RideSource = overlappingConfidences.isEmpty ? .gpsTracked : .merged
            let confidence = overlappingConfidences.max() ?? 2
            if let ride = rideFromTracked(tracked, source: source, confidence: confidence) {
                rides.append(ride)
            }
        }

        // 2) 未被「保留下来的 merged ride」覆盖的 motion 段 → motionOnly。
        //    （被丢弃的 tracked 不会产生 merged ride，其对应 motion 段会在此退化为 motionOnly。）
        let mergedRanges = rides.filter { $0.source == .merged }.map { ($0.start, $0.end) }
        for seg in motionSegments {
            let coveredByMerged = mergedRanges.contains { overlaps($0.0, $0.1, seg.start, seg.end) }
            if !coveredByMerged {
                rides.append(Ride(
                    start: seg.start, end: seg.end, source: .motionOnly,
                    distanceMeters: nil, avgSpeedMps: nil, calories: nil,
                    confidence: seg.confidence
                ))
            }
        }

        return rides.sorted { $0.start < $1.start }
    }
}
```

- [ ] **Step 4: 跑测试确认通过**

Run: `swift test --package-path Packages/CyclingDomain --filter RideReconcilerTests`
Expected: 全部 PASS

- [ ] **Step 5: 全量测试 + 提交**

Run: `swift test --package-path Packages/CyclingDomain`
Expected: 所有测试 PASS

```bash
git add Packages/CyclingDomain
git commit -m "feat(domain): RideReconciler 多源对账合并"
```

---

## M1 完成标准 (Definition of Done)

- [ ] `swift test --package-path Packages/CyclingDomain` 全绿
- [ ] 5 个逻辑文件 + 5 个测试文件齐备
- [ ] 每个 task 独立提交
- [ ] 包不依赖 CoreMotion/CoreLocation/SwiftData/UIKit（仅 Foundation），可在 CLT 环境跑

## 下一步

M2 起需要完整 Xcode。届时新开计划文件 `2026-06-16-passive-cycling-journal-m2-app-scaffold.md`。
