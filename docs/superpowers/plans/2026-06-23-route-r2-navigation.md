# 安静风景路线 R2（逐向导航）Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: superpowers:executing-plans。本机用 `DEVELOPER_DIR=/Users/sirchen/Desktop/Xcode-beta.app/Contents/Developer` 跑 `swift test` / `xcodebuild`。

**Goal:** 在 R1 算好的 RoutePlan 上做逐向导航：转向卡（下一转向 + 剩余距离）+ 地图跟随 + 语音播报 + 偏航重算 + 屏幕常亮。

**Architecture:** 转向**从折线几何自算**（航向变化角分类左右/直行/掉头），不依赖 BRouter voicehints（更稳、可单测）。导航运行时逻辑（沿线最近点投影、剩余距离、下一转向、偏航）全做成 CyclingDomain 纯函数并单测；app 层 RideNavigator 接定位+语音，RideNavigationView 显示。

**Tech Stack:** CyclingDomain（纯 Foundation）/ CoreLocation / MapKit / AVFoundation（语音）/ SwiftUI。iOS 17+。

## 文件结构
```
Packages/CyclingDomain/Sources/CyclingDomain/
  Geo.swift               # bearingDegrees, 角度归一化
  TurnDetection.swift     # TurnDirection, TurnInstruction, turnsFromPolyline
  RouteProgress.swift     # nearestPointOnRoute, NavProgress, navigationProgress
  Tests/.../GeoTests.swift
  Tests/.../TurnDetectionTests.swift
  Tests/.../RouteProgressTests.swift
Bike/Sources/Routing/
  RideNavigator.swift     # 运行时：定位→进度→推进/语音/偏航重算
Bike/Sources/UI/RideNavigationView.swift  # 导航页（转向卡+跟随地图+结束）
Bike/Sources/UI/RoutePlannerView.swift    # 加「开始导航」入口（修改）
```

---

## Task 1: 领域 — 航向 bearing

**Files:**
- Create: `Packages/CyclingDomain/Sources/CyclingDomain/Geo.swift`
- Test: `Packages/CyclingDomain/Tests/CyclingDomainTests/GeoTests.swift`

- [ ] **Step 1: 写失败测试**

```swift
import XCTest
@testable import CyclingDomain

final class GeoTests: XCTestCase {
    func test_bearingNorth() {
        let b = bearingDegrees(from: GeoCoordinate(latitude: 0, longitude: 0),
                               to: GeoCoordinate(latitude: 1, longitude: 0))
        XCTAssertEqual(b, 0, accuracy: 0.5)
    }
    func test_bearingEast() {
        let b = bearingDegrees(from: GeoCoordinate(latitude: 0, longitude: 0),
                               to: GeoCoordinate(latitude: 0, longitude: 1))
        XCTAssertEqual(b, 90, accuracy: 0.5)
    }
    func test_signedTurnRight() {
        // 由正北转向正东 = 右转 +90
        XCTAssertEqual(signedTurnDegrees(incoming: 0, outgoing: 90), 90, accuracy: 0.001)
    }
    func test_signedTurnLeftWraps() {
        // 由正北(0)转向正西(270) = 左转 -90
        XCTAssertEqual(signedTurnDegrees(incoming: 0, outgoing: 270), -90, accuracy: 0.001)
    }
}
```

- [ ] **Step 2: 跑测试确认失败**

Run: `DEVELOPER_DIR=… swift test --package-path Packages/CyclingDomain --filter GeoTests`
Expected: `cannot find 'bearingDegrees' in scope`

- [ ] **Step 3: 写实现** `Geo.swift`

```swift
import Foundation

/// 两点初始航向（0..360，正北=0，顺时针）。
public func bearingDegrees(from a: GeoCoordinate, to b: GeoCoordinate) -> Double {
    let lat1 = a.latitude * .pi / 180, lat2 = b.latitude * .pi / 180
    let dLon = (b.longitude - a.longitude) * .pi / 180
    let y = sin(dLon) * cos(lat2)
    let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon)
    let deg = atan2(y, x) * 180 / .pi
    return (deg + 360).truncatingRemainder(dividingBy: 360)
}

/// 转向角（-180..180）：正=右转，负=左转。
public func signedTurnDegrees(incoming: Double, outgoing: Double) -> Double {
    var d = (outgoing - incoming).truncatingRemainder(dividingBy: 360)
    if d > 180 { d -= 360 }
    if d < -180 { d += 360 }
    return d
}
```

- [ ] **Step 4: 跑测试确认通过** → `swift test --filter GeoTests` 全 PASS
- [ ] **Step 5: 提交** `git commit -m "feat(domain): 航向 bearing + 转向角（R2）"`

---

## Task 2: 领域 — 从折线检测转向

**Files:**
- Create: `Packages/CyclingDomain/Sources/CyclingDomain/TurnDetection.swift`
- Test: `Packages/CyclingDomain/Tests/CyclingDomainTests/TurnDetectionTests.swift`

- [ ] **Step 1: 写失败测试**

```swift
import XCTest
@testable import CyclingDomain

final class TurnDetectionTests: XCTestCase {
    func test_straightLineNoTurns() {
        let coords = [GeoCoordinate(latitude: 0, longitude: 0),
                      GeoCoordinate(latitude: 0.001, longitude: 0),
                      GeoCoordinate(latitude: 0.002, longitude: 0)]
        let turns = turnsFromPolyline(coords)
        XCTAssertEqual(turns.filter { $0.direction != .arrive }.count, 0)
        XCTAssertEqual(turns.last?.direction, .arrive)
    }

    func test_rightTurnDetected() {
        // 向北走，然后向东 = 右转
        let coords = [GeoCoordinate(latitude: 0, longitude: 0),
                      GeoCoordinate(latitude: 0.001, longitude: 0),
                      GeoCoordinate(latitude: 0.001, longitude: 0.001)]
        let turns = turnsFromPolyline(coords)
        let real = turns.filter { $0.direction != .arrive }
        XCTAssertEqual(real.count, 1)
        XCTAssertEqual(real.first?.direction, .right)
        XCTAssertEqual(real.first?.coordinateIndex, 1)
    }

    func test_leftTurnDetected() {
        let coords = [GeoCoordinate(latitude: 0, longitude: 0),
                      GeoCoordinate(latitude: 0.001, longitude: 0),
                      GeoCoordinate(latitude: 0.001, longitude: -0.001)]
        let turns = turnsFromPolyline(coords).filter { $0.direction != .arrive }
        XCTAssertEqual(turns.first?.direction, .left)
    }
}
```

- [ ] **Step 2: 跑测试确认失败** → `cannot find 'turnsFromPolyline'`

- [ ] **Step 3: 写实现** `TurnDetection.swift`

```swift
import Foundation

public enum TurnDirection: String, Sendable, Equatable {
    case straight, slightLeft, left, sharpLeft, slightRight, right, sharpRight, uTurn, arrive
}

public struct TurnInstruction: Equatable, Sendable {
    public let coordinateIndex: Int
    public let direction: TurnDirection
    public let distanceFromPreviousMeters: Double
    public init(coordinateIndex: Int, direction: TurnDirection, distanceFromPreviousMeters: Double) {
        self.coordinateIndex = coordinateIndex
        self.direction = direction
        self.distanceFromPreviousMeters = distanceFromPreviousMeters
    }
}

/// 角度（绝对值）→ 转向方向（带左右符号）。
private func classify(_ signed: Double) -> TurnDirection {
    let a = abs(signed)
    let right = signed > 0
    switch a {
    case ..<20:  return .straight
    case ..<45:  return right ? .slightRight : .slightLeft
    case ..<120: return right ? .right : .left
    case ..<160: return right ? .sharpRight : .sharpLeft
    default:     return .uTurn
    }
}

/// 从折线顶点的航向变化检测转向。末尾追加 .arrive。
/// `distanceFromPreviousMeters`：距上一个转向/起点的沿线距离。
public func turnsFromPolyline(_ coords: [GeoCoordinate], minTurnAngle: Double = 20) -> [TurnInstruction] {
    guard coords.count >= 2 else { return [] }
    var turns: [TurnInstruction] = []
    var accumulated = 0.0
    var sinceLast = 0.0

    for i in 1..<coords.count {
        let segLen = haversineMeters(
            lat1: coords[i - 1].latitude, lon1: coords[i - 1].longitude,
            lat2: coords[i].latitude, lon2: coords[i].longitude)
        accumulated += segLen
        sinceLast += segLen

        if i < coords.count - 1 {
            let incoming = bearingDegrees(from: coords[i - 1], to: coords[i])
            let outgoing = bearingDegrees(from: coords[i], to: coords[i + 1])
            let signed = signedTurnDegrees(incoming: incoming, outgoing: outgoing)
            let dir = classify(signed)
            if dir != .straight {
                turns.append(TurnInstruction(coordinateIndex: i, direction: dir, distanceFromPreviousMeters: sinceLast))
                sinceLast = 0
            }
        }
    }
    turns.append(TurnInstruction(coordinateIndex: coords.count - 1, direction: .arrive, distanceFromPreviousMeters: sinceLast))
    return turns
}
```

- [ ] **Step 4: 跑测试确认通过** → `swift test --filter TurnDetectionTests` 全 PASS
- [ ] **Step 5: 提交** `git commit -m "feat(domain): 折线几何检测转向（R2）"`

---

## Task 3: 领域 — 最近点投影 + 导航进度

**Files:**
- Create: `Packages/CyclingDomain/Sources/CyclingDomain/RouteProgress.swift`
- Test: `Packages/CyclingDomain/Tests/CyclingDomainTests/RouteProgressTests.swift`

- [ ] **Step 1: 写失败测试**

```swift
import XCTest
@testable import CyclingDomain

final class RouteProgressTests: XCTestCase {
    private let line = [GeoCoordinate(latitude: 0, longitude: 0),
                        GeoCoordinate(latitude: 0, longitude: 0.01)] // 沿赤道向东约 1.11km

    func test_nearestOnSegmentDistance() {
        // 点在线北侧约 111m（纬度 +0.001）
        let p = GeoCoordinate(latitude: 0.001, longitude: 0.005)
        let r = nearestPointOnRoute(p, line)
        XCTAssertEqual(r.distanceMeters, 111.2, accuracy: 5)
        XCTAssertEqual(r.segmentIndex, 0)
    }

    func test_onRouteNotOffRoute() {
        let p = GeoCoordinate(latitude: 0.0001, longitude: 0.005) // ~11m 偏
        let r = nearestPointOnRoute(p, line)
        XCTAssertFalse(isOffRoute(distanceToRouteMeters: r.distanceMeters))
    }

    func test_offRouteWhenFar() {
        XCTAssertTrue(isOffRoute(distanceToRouteMeters: 80))
    }
}
```

- [ ] **Step 2: 跑测试确认失败** → `cannot find 'nearestPointOnRoute'`

- [ ] **Step 3: 写实现** `RouteProgress.swift`

```swift
import Foundation

public struct NearestResult: Equatable, Sendable {
    public let segmentIndex: Int
    public let distanceMeters: Double
    public let projection: GeoCoordinate
}

/// 把点投影到折线，返回最近段、垂距（米）、投影点。
/// 用局部等距平面近似（小范围足够准）。
public func nearestPointOnRoute(_ p: GeoCoordinate, _ coords: [GeoCoordinate]) -> NearestResult {
    precondition(coords.count >= 2)
    let mLatToM = 111_320.0
    let mLonToM = 111_320.0 * cos(p.latitude * .pi / 180)
    func xy(_ c: GeoCoordinate) -> (Double, Double) {
        ((c.longitude - p.longitude) * mLonToM, (c.latitude - p.latitude) * mLatToM)
    }
    var best = NearestResult(segmentIndex: 0, distanceMeters: .infinity, projection: coords[0])
    for i in 0..<(coords.count - 1) {
        let (ax, ay) = xy(coords[i])
        let (bx, by) = xy(coords[i + 1])
        let dx = bx - ax, dy = by - ay
        let len2 = dx * dx + dy * dy
        let t = len2 > 0 ? max(0, min(1, -(ax * dx + ay * dy) / len2)) : 0
        let px = ax + t * dx, py = ay + t * dy
        let dist = (px * px + py * py).squareRoot()
        if dist < best.distanceMeters {
            let proj = GeoCoordinate(
                latitude: p.latitude + py / mLatToM,
                longitude: p.longitude + px / mLonToM)
            best = NearestResult(segmentIndex: i, distanceMeters: dist, projection: proj)
        }
    }
    return best
}

/// 偏航判定（默认阈值 40m）。
public func isOffRoute(distanceToRouteMeters: Double, threshold: Double = 40) -> Bool {
    distanceToRouteMeters > threshold
}

public struct NavProgress: Equatable, Sendable {
    public let segmentIndex: Int
    public let distanceToRouteMeters: Double
    public let isOffRoute: Bool
    public let nextTurn: TurnInstruction?
    public let distanceToNextTurnMeters: Double
}

/// 综合：最近点 + 下一转向 + 到下一转向距离 + 偏航。
public func navigationProgress(
    location: GeoCoordinate, coords: [GeoCoordinate], turns: [TurnInstruction]
) -> NavProgress {
    let near = nearestPointOnRoute(location, coords)
    let off = isOffRoute(distanceToRouteMeters: near.distanceMeters)

    // 下一转向：coordinateIndex 在当前段之后的第一个
    let next = turns.first { $0.coordinateIndex > near.segmentIndex }
    var distToTurn = 0.0
    if let next {
        // 当前投影点 → 段末点
        distToTurn += haversineMeters(
            lat1: near.projection.latitude, lon1: near.projection.longitude,
            lat2: coords[near.segmentIndex + 1].latitude, lon2: coords[near.segmentIndex + 1].longitude)
        // 之后各段累加直到 turn 顶点
        var i = near.segmentIndex + 1
        while i < next.coordinateIndex {
            distToTurn += haversineMeters(
                lat1: coords[i].latitude, lon1: coords[i].longitude,
                lat2: coords[i + 1].latitude, lon2: coords[i + 1].longitude)
            i += 1
        }
    }
    return NavProgress(
        segmentIndex: near.segmentIndex,
        distanceToRouteMeters: near.distanceMeters,
        isOffRoute: off,
        nextTurn: next,
        distanceToNextTurnMeters: distToTurn)
}
```

- [ ] **Step 4: 跑测试确认通过** → `swift test --filter RouteProgressTests` 全 PASS
- [ ] **Step 5: 全量域测试 + 提交**

Run: `DEVELOPER_DIR=… swift test --package-path Packages/CyclingDomain`
```bash
git add Packages/CyclingDomain
git commit -m "feat(domain): 最近点投影 + 导航进度 + 偏航（R2）"
```

---

## Task 4: RideNavigator（运行时）

**Files:**
- Create: `Bike/Sources/Routing/RideNavigator.swift`

- [ ] **Step 1: 写实现**

```swift
import Foundation
import CoreLocation
import AVFoundation
import CyclingDomain
import Observation

/// 导航运行时：定位 → navigationProgress → 更新转向卡、语音、偏航重算。
@MainActor
@Observable
final class RideNavigator: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private let speech = AVSpeechSynthesizer()
    private let service = RouteService()

    private(set) var coords: [GeoCoordinate]
    private(set) var turns: [TurnInstruction]
    private(set) var progress: NavProgress?
    private(set) var arrived = false
    private let destination: GeoCoordinate
    private var lastSpokenTurnIndex: Int?
    private var offRouteSince: Date?
    private var rerouting = false

    var voiceEnabled = true

    init(plan: RoutePlan, destination: GeoCoordinate) {
        self.coords = plan.coordinates
        self.turns = turnsFromPolyline(plan.coordinates)
        self.destination = destination
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
    }

    func start() {
        manager.requestWhenInUseAuthorization()
        manager.startUpdatingLocation()
    }

    func stop() {
        manager.stopUpdatingLocation()
    }

    private func handle(_ loc: GeoCoordinate) {
        guard !coords.isEmpty else { return }
        let p = navigationProgress(location: loc, coords: coords, turns: turns)
        progress = p

        // 到达
        if let next = p.nextTurn, next.direction == .arrive, p.distanceToNextTurnMeters < 25 {
            arrived = true
            speak("已到达目的地")
            stop()
            return
        }
        // 语音：接近转向（150m / 30m 各播一次）
        if let next = p.nextTurn, next.direction != .arrive {
            if p.distanceToNextTurnMeters < 150, lastSpokenTurnIndex != next.coordinateIndex {
                lastSpokenTurnIndex = next.coordinateIndex
                speak("前方 \(Int(p.distanceToNextTurnMeters)) 米，\(phrase(next.direction))")
            }
        }
        // 偏航重算
        if p.isOffRoute {
            if offRouteSince == nil { offRouteSince = Date() }
            if let since = offRouteSince, Date().timeIntervalSince(since) > 8, !rerouting {
                Task { await reroute(from: loc) }
            }
        } else {
            offRouteSince = nil
        }
    }

    private func reroute(from loc: GeoCoordinate) async {
        rerouting = true
        defer { rerouting = false }
        if case .success(let plan) = await service.route(from: loc, to: destination) {
            coords = plan.coordinates
            turns = turnsFromPolyline(plan.coordinates)
            lastSpokenTurnIndex = nil
            offRouteSince = nil
            speak("已重新规划路线")
        }
    }

    private func speak(_ text: String) {
        guard voiceEnabled else { return }
        let u = AVSpeechUtterance(string: text)
        u.voice = AVSpeechSynthesisVoice(language: "zh-CN")
        speech.speak(u)
    }

    private func phrase(_ d: TurnDirection) -> String {
        switch d {
        case .left, .slightLeft: return "向左"
        case .sharpLeft: return "向左急转"
        case .right, .slightRight: return "向右"
        case .sharpRight: return "向右急转"
        case .uTurn: return "掉头"
        case .straight: return "直行"
        case .arrive: return "到达"
        }
    }

    nonisolated func locationManager(_ m: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let last = locations.last else { return }
        let c = GeoCoordinate(latitude: last.coordinate.latitude, longitude: last.coordinate.longitude)
        Task { @MainActor in self.handle(c) }
    }
}
```

- [ ] **Step 2: 提交** `git commit -m "feat(route): RideNavigator 导航运行时（R2）"`

---

## Task 5: RideNavigationView + 入口

**Files:**
- Create: `Bike/Sources/UI/RideNavigationView.swift`
- Modify: `Bike/Sources/UI/RoutePlannerView.swift`（加「开始导航」）

- [ ] **Step 1: 写 RideNavigationView**

```swift
import SwiftUI
import MapKit
import CyclingDomain

struct RideNavigationView: View {
    @State private var navigator: RideNavigator
    @Environment(\.dismiss) private var dismiss

    init(plan: RoutePlan, destination: GeoCoordinate) {
        _navigator = State(initialValue: RideNavigator(plan: plan, destination: destination))
    }

    var body: some View {
        ZStack(alignment: .top) {
            Map {
                let cs = navigator.coords.map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) }
                if cs.count >= 2 { MapPolyline(coordinates: cs).stroke(.tint, lineWidth: 5) }
                UserAnnotation()
            }
            .mapControls { MapUserLocationButton() }
            .ignoresSafeArea()

            turnCard

            VStack {
                Spacer()
                Button(role: .destructive) { navigator.stop(); dismiss() } label: {
                    Label("结束导航", systemImage: "xmark.circle.fill").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent).tint(.red).padding()
            }
        }
        .onAppear {
            UIApplication.shared.isIdleTimerDisabled = true
            navigator.start()
        }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
            navigator.stop()
        }
        .alert("已到达目的地", isPresented: .constant(navigator.arrived)) {
            Button("完成") { dismiss() }
        }
    }

    private var turnCard: some View {
        HStack(spacing: 12) {
            Image(systemName: icon(navigator.progress?.nextTurn?.direction))
                .font(.system(size: 30, weight: .bold))
            VStack(alignment: .leading) {
                if let p = navigator.progress, let t = p.nextTurn, t.direction != .arrive {
                    Text("\(Int(p.distanceToNextTurnMeters)) 米").font(.title3.bold())
                    Text(phrase(t.direction)).font(.subheadline)
                } else {
                    Text("沿路线前进").font(.headline)
                }
            }
            Spacer()
        }
        .padding()
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .padding()
    }

    private func icon(_ d: TurnDirection?) -> String {
        switch d {
        case .left, .slightLeft, .sharpLeft: return "arrow.turn.up.left"
        case .right, .slightRight, .sharpRight: return "arrow.turn.up.right"
        case .uTurn: return "arrow.uturn.down"
        case .arrive: return "flag.checkered"
        default: return "arrow.up"
        }
    }
    private func phrase(_ d: TurnDirection) -> String {
        switch d {
        case .left, .slightLeft: return "向左"
        case .sharpLeft: return "向左急转"
        case .right, .slightRight: return "向右"
        case .sharpRight: return "向右急转"
        case .uTurn: return "掉头"
        case .straight: return "直行"
        case .arrive: return "到达"
        }
    }
}
```

- [ ] **Step 2: 在 RoutePlannerView 的「路线」section 加「开始导航」**

在 `plan` section 末尾、`Label("已尽量避开主干道"...)` 之后加：

```swift
                        NavigationLink {
                            RideNavigationView(coordinates路线: plan, destination: lastDestination)
                        } label: {
                            Label("开始导航", systemImage: "location.north.line.fill")
                        }
```

（注：在 RoutePlannerView 加 `@State private var lastDestination: GeoCoordinate?`，`planRoute(to:)` 成功时记 `lastDestination = dest.coordinate`；NavigationLink 用 `if let lastDestination`。具体接线在实现时按编译调整。）

- [ ] **Step 3: 构建**

Run: `DEVELOPER_DIR=… xcodebuild -project Bike.xcodeproj -scheme Bike -destination 'platform=iOS Simulator,name=iPhone 17' -configuration Debug CODE_SIGNING_ALLOWED=NO build`
Expected: BUILD SUCCEEDED

- [ ] **Step 4: 真机手验**：联网算路 → 开始导航 → 走动看转向卡推进 / 语音 / 偏航重算（模拟器可用 Features→Location→Freeway Drive 模拟移动）

- [ ] **Step 5: 提交** `git commit -m "feat(route): R2 逐向导航页 + 入口"`

---

## R2 完成标准
- [ ] 域测试全绿（bearing/转向检测/最近点/进度/偏航）
- [ ] app 构建通过
- [ ] 模拟器 Freeway Drive 或真机：转向卡随移动推进、接近转向语音、偏航重算

## 备注
- 转向用几何自算（MVP）；BRouter voicehints 精确转向留 v2。
- 语音用 `AVSpeechSynthesizer` zh-CN。
