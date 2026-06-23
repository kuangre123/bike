# 安静风景路线 R1（规划 + 显示）Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: superpowers:executing-plans 或 subagent-driven-development。本机用 `DEVELOPER_DIR=/Users/sirchen/Desktop/Xcode-beta.app/Contents/Developer` 前缀跑 `swift test` / `xcodebuild`。

**Goal:** 选目的地（搜索/地图点选）→ 调 BRouter 安静 profile 算一条避主干道的骑行路线 → 地图显示折线 + 距离 + 预计时间。独立「路线」tab。联网默认关、首次同意。

**Architecture:** 领域层（CyclingDomain，纯 Foundation）解析 BRouter geojson + 算折线长度（可单测）；app 层 RouteService 联网、DestinationSearch 搜地点、RoutePlannerView 展示；根改 TabView。转向导航是 R2。

**Tech Stack:** SwiftUI TabView / MapKit / MKLocalSearch / URLSession / CyclingDomain。iOS 17+。

## 前置
- 算路引擎 BRouter 公共服务器：`https://brouter.de/brouter?lonlats=lon,lat|lon,lat&profile=trekking&alternativeidx=0&format=geojson`
- 响应 GeoJSON：`features[0].geometry.coordinates`=[[lon,lat,ele]...]，`properties.track-length`(米,字符串)、`properties.total-time`(秒,字符串)。
- voicehints（转向）R1 不解析，留 R2。

## 文件结构
```
Packages/CyclingDomain/Sources/CyclingDomain/
  RoutePlan.swift            # GeoCoordinate, RoutePlan, polylineLengthMeters
  BRouterParsing.swift       # parseBRouterGeoJSON
  Tests/.../RoutePlanTests.swift
  Tests/.../BRouterParsingTests.swift
Bike/Sources/Routing/
  RoutePrefs.swift           # 联网同意开关
  RouteService.swift         # BRouter 客户端
  DestinationSearch.swift    # MKLocalSearch 封装
Bike/Sources/UI/RoutePlannerView.swift   # 路线 tab 界面
Bike/Sources/App/BikeApp.swift           # 改 TabView（修改）
```

---

## Task 1: 领域 — GeoCoordinate / RoutePlan / 折线长度

**Files:**
- Create: `Packages/CyclingDomain/Sources/CyclingDomain/RoutePlan.swift`
- Test: `Packages/CyclingDomain/Tests/CyclingDomainTests/RoutePlanTests.swift`

- [ ] **Step 1: 写失败测试**

```swift
import XCTest
@testable import CyclingDomain

final class RoutePlanTests: XCTestCase {
    func test_polylineLengthTwoPoints() {
        // 纬度差 0.001 ≈ 111.2 m
        let coords = [GeoCoordinate(latitude: 0, longitude: 0),
                      GeoCoordinate(latitude: 0.001, longitude: 0)]
        XCTAssertEqual(polylineLengthMeters(coords), 111.2, accuracy: 1.0)
    }

    func test_polylineLengthFewerThanTwoIsZero() {
        XCTAssertEqual(polylineLengthMeters([]), 0)
        XCTAssertEqual(polylineLengthMeters([GeoCoordinate(latitude: 1, longitude: 1)]), 0)
    }

    func test_routePlanDurationMinutes() {
        let plan = RoutePlan(coordinates: [], distanceMeters: 0, estimatedSeconds: 1800)
        XCTAssertEqual(plan.estimatedMinutes, 30)
    }
}
```

- [ ] **Step 2: 跑测试确认失败**

Run: `DEVELOPER_DIR=/Users/sirchen/Desktop/Xcode-beta.app/Contents/Developer swift test --package-path Packages/CyclingDomain --filter RoutePlanTests`
Expected: 编译失败 `cannot find 'GeoCoordinate' in scope`

- [ ] **Step 3: 写实现** `RoutePlan.swift`

```swift
import Foundation

/// 轻量地理坐标（路线用；不带时间/速度，区别于 GPSSample）。
public struct GeoCoordinate: Equatable, Sendable {
    public let latitude: Double
    public let longitude: Double
    public init(latitude: Double, longitude: Double) {
        self.latitude = latitude
        self.longitude = longitude
    }
}

/// 一条算好的骑行路线。
public struct RoutePlan: Equatable, Sendable {
    public let coordinates: [GeoCoordinate]
    public let distanceMeters: Double
    public let estimatedSeconds: Double
    public init(coordinates: [GeoCoordinate], distanceMeters: Double, estimatedSeconds: Double) {
        self.coordinates = coordinates
        self.distanceMeters = distanceMeters
        self.estimatedSeconds = estimatedSeconds
    }
    public var estimatedMinutes: Int { Int((estimatedSeconds / 60).rounded()) }
}

/// 折线累计长度（米），复用 haversine。
public func polylineLengthMeters(_ coords: [GeoCoordinate]) -> Double {
    guard coords.count >= 2 else { return 0 }
    var total = 0.0
    for i in 1..<coords.count {
        total += haversineMeters(
            lat1: coords[i - 1].latitude, lon1: coords[i - 1].longitude,
            lat2: coords[i].latitude, lon2: coords[i].longitude)
    }
    return total
}
```

- [ ] **Step 4: 跑测试确认通过**

Run: `DEVELOPER_DIR=… swift test --package-path Packages/CyclingDomain --filter RoutePlanTests`
Expected: 全部 PASS

- [ ] **Step 5: 提交**

```bash
git add Packages/CyclingDomain
git commit -m "feat(domain): RoutePlan + GeoCoordinate + 折线长度"
```

---

## Task 2: 领域 — 解析 BRouter GeoJSON

**Files:**
- Create: `Packages/CyclingDomain/Sources/CyclingDomain/BRouterParsing.swift`
- Test: `Packages/CyclingDomain/Tests/CyclingDomainTests/BRouterParsingTests.swift`

- [ ] **Step 1: 写失败测试**

```swift
import XCTest
@testable import CyclingDomain

final class BRouterParsingTests: XCTestCase {
    private let sample = """
    {"type":"FeatureCollection","features":[{"type":"Feature",
    "properties":{"track-length":"1500","total-time":"360"},
    "geometry":{"type":"LineString","coordinates":[
    [116.0,39.0,40],[116.001,39.001,41],[116.002,39.002,42]]}}]}
    """

    func test_parsesCoordinatesDistanceTime() {
        let plan = parseBRouterGeoJSON(Data(sample.utf8))
        XCTAssertNotNil(plan)
        XCTAssertEqual(plan?.coordinates.count, 3)
        // geojson 是 [lon,lat]，解析后 lat=39.0, lon=116.0
        XCTAssertEqual(plan?.coordinates.first?.latitude, 39.0)
        XCTAssertEqual(plan?.coordinates.first?.longitude, 116.0)
        XCTAssertEqual(plan?.distanceMeters, 1500)
        XCTAssertEqual(plan?.estimatedSeconds, 360)
    }

    func test_invalidJSONReturnsNil() {
        XCTAssertNil(parseBRouterGeoJSON(Data("not json".utf8)))
    }

    func test_missingDistanceFallsBackToPolylineLength() {
        let noLen = """
        {"features":[{"properties":{},"geometry":{"type":"LineString",
        "coordinates":[[0,0,0],[0,0.001,0]]}}]}
        """
        let plan = parseBRouterGeoJSON(Data(noLen.utf8))
        XCTAssertEqual(plan?.distanceMeters ?? 0, 111.2, accuracy: 1.0)
    }
}
```

- [ ] **Step 2: 跑测试确认失败**

Run: `DEVELOPER_DIR=… swift test --package-path Packages/CyclingDomain --filter BRouterParsingTests`
Expected: 编译失败 `cannot find 'parseBRouterGeoJSON' in scope`

- [ ] **Step 3: 写实现** `BRouterParsing.swift`

```swift
import Foundation

/// 解析 BRouter 的 GeoJSON 响应为 RoutePlan。失败返回 nil。
/// 距离取 properties.track-length（米，字符串）；缺失则用折线长度兜底。
public func parseBRouterGeoJSON(_ data: Data) -> RoutePlan? {
    guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let features = obj["features"] as? [[String: Any]],
          let feature = features.first,
          let geometry = feature["geometry"] as? [String: Any],
          let rawCoords = geometry["coordinates"] as? [[Double]]
    else { return nil }

    let coordinates: [GeoCoordinate] = rawCoords.compactMap { c in
        guard c.count >= 2 else { return nil }
        return GeoCoordinate(latitude: c[1], longitude: c[0]) // geojson: [lon, lat]
    }
    guard coordinates.count >= 2 else { return nil }

    let props = feature["properties"] as? [String: Any]
    let distance = (props?["track-length"] as? String).flatMap(Double.init)
        ?? polylineLengthMeters(coordinates)
    let seconds = (props?["total-time"] as? String).flatMap(Double.init) ?? 0

    return RoutePlan(coordinates: coordinates, distanceMeters: distance, estimatedSeconds: seconds)
}
```

- [ ] **Step 4: 跑测试确认通过**

Run: `DEVELOPER_DIR=… swift test --package-path Packages/CyclingDomain --filter BRouterParsingTests`
Expected: 全部 PASS

- [ ] **Step 5: 全量域测试 + 提交**

Run: `DEVELOPER_DIR=… swift test --package-path Packages/CyclingDomain`
Expected: 全部 PASS

```bash
git add Packages/CyclingDomain
git commit -m "feat(domain): 解析 BRouter GeoJSON 为 RoutePlan"
```

---

## Task 3: 联网同意开关 RoutePrefs

**Files:**
- Create: `Bike/Sources/Routing/RoutePrefs.swift`

- [ ] **Step 1: 写实现**

```swift
import Foundation

/// 路线功能的联网同意（默认关）。键 "routeNetworkEnabled"。
enum RoutePrefs {
    private static let key = "routeNetworkEnabled"

    static var networkEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: key) }
        set { UserDefaults.standard.set(newValue, forKey: key) }
    }
}
```

- [ ] **Step 2: 提交**

```bash
git add Bike/Sources/Routing/RoutePrefs.swift
git commit -m "feat(route): 联网同意开关 RoutePrefs（默认关）"
```

---

## Task 4: BRouter 客户端 RouteService

**Files:**
- Create: `Bike/Sources/Routing/RouteService.swift`

- [ ] **Step 1: 写实现**

```swift
import Foundation
import CyclingDomain

enum RouteError: Error, Equatable {
    case networkDisabled
    case offline
    case noRoute
    case server
}

/// 调 BRouter 公共服务器算一条安静（trekking）骑行路线。
struct RouteService {
    var baseURL = "https://brouter.de/brouter"
    var session: URLSession = .shared

    func route(
        from: GeoCoordinate, to: GeoCoordinate, profile: String = "trekking"
    ) async -> Result<RoutePlan, RouteError> {
        guard RoutePrefs.networkEnabled else { return .failure(.networkDisabled) }
        let lonlats = "\(from.longitude),\(from.latitude)|\(to.longitude),\(to.latitude)"
        var comps = URLComponents(string: baseURL)!
        comps.queryItems = [
            .init(name: "lonlats", value: lonlats),
            .init(name: "profile", value: profile),
            .init(name: "alternativeidx", value: "0"),
            .init(name: "format", value: "geojson"),
        ]
        guard let url = comps.url else { return .failure(.server) }
        do {
            let (data, response) = try await session.data(from: url)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                return .failure(.server)
            }
            guard let plan = parseBRouterGeoJSON(data) else { return .failure(.noRoute) }
            return .success(plan)
        } catch {
            return .failure(.offline)
        }
    }
}
```

- [ ] **Step 2: 提交**

```bash
git add Bike/Sources/Routing/RouteService.swift
git commit -m "feat(route): BRouter 客户端 RouteService"
```

---

## Task 5: 目的地搜索 DestinationSearch

**Files:**
- Create: `Bike/Sources/Routing/DestinationSearch.swift`

- [ ] **Step 1: 写实现**

```swift
import Foundation
import MapKit
import CyclingDomain

struct Destination: Identifiable, Equatable {
    let id = UUID()
    let name: String
    let subtitle: String
    let coordinate: GeoCoordinate
}

/// MKLocalSearch 封装：关键词 → 候选地点（按当前区域偏置）。
@MainActor
struct DestinationSearch {
    func search(_ query: String, near center: GeoCoordinate) async -> [Destination] {
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else { return [] }
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        request.region = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: center.latitude, longitude: center.longitude),
            latitudinalMeters: 30_000, longitudinalMeters: 30_000)
        guard let response = try? await MKLocalSearch(request: request).start() else { return [] }
        return response.mapItems.map { item in
            Destination(
                name: item.name ?? "未知地点",
                subtitle: item.placemark.title ?? "",
                coordinate: GeoCoordinate(
                    latitude: item.placemark.coordinate.latitude,
                    longitude: item.placemark.coordinate.longitude))
        }
    }
}
```

- [ ] **Step 2: 提交**

```bash
git add Bike/Sources/Routing/DestinationSearch.swift
git commit -m "feat(route): 目的地搜索 DestinationSearch (MKLocalSearch)"
```

---

## Task 6: 路线 tab 界面 + TabView 改造

**Files:**
- Create: `Bike/Sources/UI/RoutePlannerView.swift`
- Modify: `Bike/Sources/App/BikeApp.swift`

- [ ] **Step 1: 写 RoutePlannerView**

```swift
import SwiftUI
import MapKit
import CoreLocation
import CyclingDomain

struct RoutePlannerView: View {
    @State private var query = ""
    @State private var results: [Destination] = []
    @State private var plan: RoutePlan?
    @State private var loading = false
    @State private var errorText: String?
    @State private var showConsent = false
    @AppStorage("routeNetworkEnabled") private var networkEnabled = false

    private let locationManager = CLLocationManager()
    private let search = DestinationSearch()
    private let service = RouteService()

    var body: some View {
        NavigationStack {
            List {
                Section {
                    TextField("搜索目的地", text: $query)
                        .onSubmit { Task { await runSearch() } }
                }
                if let plan {
                    Section("路线") {
                        RoutePreviewMap(coordinates: plan.coordinates)
                            .frame(height: 220)
                            .listRowInsets(EdgeInsets())
                        LabeledContent("距离", value: String(format: "%.1f 公里", plan.distanceMeters / 1000))
                        LabeledContent("预计", value: "\(plan.estimatedMinutes) 分钟")
                        Label("已尽量避开主干道", systemImage: "leaf").font(.caption).foregroundStyle(.secondary)
                    }
                }
                if let errorText {
                    Text(errorText).font(.caption).foregroundStyle(.red)
                }
                Section("附近地点") {
                    ForEach(results) { dest in
                        Button {
                            Task { await planRoute(to: dest) }
                        } label: {
                            VStack(alignment: .leading) {
                                Text(dest.name)
                                Text(dest.subtitle).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .navigationTitle("路线")
            .overlay { if loading { ProgressView() } }
            .sheet(isPresented: $showConsent) { consentSheet }
            .onAppear { locationManager.requestWhenInUseAuthorization() }
        }
    }

    private var consentSheet: some View {
        VStack(spacing: 16) {
            Text("路线规划需要联网").font(.headline)
            Text("规划路线会把你的起点与目的地坐标发送给地图路线服务（brouter.de）。仅用于算路，不做其他用途。")
                .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
            Button("同意并启用") { networkEnabled = true; showConsent = false }
                .buttonStyle(.borderedProminent)
            Button("取消", role: .cancel) { showConsent = false }
        }.padding()
    }

    private func currentCoordinate() -> GeoCoordinate? {
        guard let loc = locationManager.location else { return nil }
        return GeoCoordinate(latitude: loc.coordinate.latitude, longitude: loc.coordinate.longitude)
    }

    private func runSearch() async {
        let center = currentCoordinate() ?? GeoCoordinate(latitude: 39.9, longitude: 116.4)
        results = await search.search(query, near: center)
    }

    private func planRoute(to dest: Destination) async {
        guard networkEnabled else { showConsent = true; return }
        guard let from = currentCoordinate() else { errorText = "无法获取当前位置"; return }
        loading = true; errorText = nil
        let result = await service.route(from: from, to: dest.coordinate)
        loading = false
        switch result {
        case .success(let p): plan = p
        case .failure(let e): errorText = message(for: e)
        }
    }

    private func message(for error: RouteError) -> String {
        switch error {
        case .networkDisabled: return "未启用联网"
        case .offline: return "网络不可用"
        case .noRoute: return "没找到合适的路线"
        case .server: return "路线服务暂时不可用"
        }
    }
}

/// 只读路线预览地图。
private struct RoutePreviewMap: View {
    let coordinates: [GeoCoordinate]
    var body: some View {
        let coords = coordinates.map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) }
        Map(initialPosition: .region(region(coords))) {
            if coords.count >= 2 { MapPolyline(coordinates: coords).stroke(.tint, lineWidth: 4) }
            if let s = coords.first { Marker("起点", coordinate: s).tint(.green) }
            if let e = coords.last { Marker("终点", coordinate: e).tint(.red) }
        }
    }
    private func region(_ coords: [CLLocationCoordinate2D]) -> MKCoordinateRegion {
        guard !coords.isEmpty else {
            return MKCoordinateRegion(center: .init(latitude: 39.9, longitude: 116.4),
                                      span: .init(latitudeDelta: 0.1, longitudeDelta: 0.1))
        }
        let lats = coords.map(\.latitude), lons = coords.map(\.longitude)
        let c = CLLocationCoordinate2D(latitude: (lats.min()! + lats.max()!) / 2,
                                       longitude: (lons.min()! + lons.max()!) / 2)
        let span = MKCoordinateSpan(latitudeDelta: max(0.01, (lats.max()! - lats.min()!) * 1.4),
                                    longitudeDelta: max(0.01, (lons.max()! - lons.min()!) * 1.4))
        return MKCoordinateRegion(center: c, span: span)
    }
}
```

- [ ] **Step 2: 改 BikeApp 为 TabView**

把 `WindowGroup` 内容从直接 `RideTimelineView()` 改为 `TabView`：

```swift
        WindowGroup {
            TabView {
                RideTimelineView()
                    .environment(permissions)
                    .environment(coordinator)
                    .tabItem { Label("运动", systemImage: "figure.run") }
                RoutePlannerView()
                    .tabItem { Label("路线", systemImage: "map") }
            }
            .task {
                #if DEBUG
                let env = ProcessInfo.processInfo.environment
                if env["SEED_SAMPLE"] == "1" || env["OPEN_FIRST_DETAIL"] == "1" { return }
                #endif
                coordinator.start()
                BackgroundReconcileTask.schedule()
            }
        }
        .modelContainer(container)
```

- [ ] **Step 3: 构建验证**

Run:
```
DEVELOPER_DIR=/Users/sirchen/Desktop/Xcode-beta.app/Contents/Developer xcodegen generate
DEVELOPER_DIR=… xcodebuild -project Bike.xcodeproj -scheme Bike -destination 'platform=iOS Simulator,name=iPhone 17' -configuration Debug CODE_SIGNING_ALLOWED=NO build
```
Expected: `BUILD SUCCEEDED`

- [ ] **Step 4: 模拟器手验**

模拟器启用「路线」tab → 首次点目的地弹联网同意 → 同意后搜索（如"公园"）→ 选一条 → 看到折线 + 距离 + 时间。（模拟器需联网；定位用 Features→Location 设一个城市。）

- [ ] **Step 5: 提交**

```bash
git add Bike/Sources/UI/RoutePlannerView.swift Bike/Sources/App/BikeApp.swift
git commit -m "feat(route): R1 路线 tab — 搜索/算路/折线显示 + TabView 改造"
```

---

## R1 完成标准
- [ ] `swift test` 域全绿（含 RoutePlan/BRouter 解析新测试）
- [ ] app 构建通过（TabView 双 tab）
- [ ] 模拟器：路线 tab 能搜索→算路→显示折线/距离/时间，联网默认关需同意

## 下一步
R2 逐向导航：解析 voicehints → TurnInstruction、`nearestPointOnRoute`/`navigationProgress`/偏航（领域单测）+ RideNavigator + 导航页 + 语音 + 偏航重算。新计划文件 `2026-06-23-route-r2-navigation.md`。
