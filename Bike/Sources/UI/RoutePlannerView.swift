import SwiftUI
import MapKit
import CoreLocation
import CyclingDomain

/// 「路线」tab：搜索/选目的地 → BRouter 安静路线 → 折线 + 距离 + 时间。
struct RoutePlannerView: View {
    @State private var query = ""
    @State private var results: [Destination] = []
    @State private var plan: RoutePlan?
    @State private var lastDestination: GeoCoordinate?
    @State private var loading = false
    @State private var errorText: String?
    @State private var showConsent = false
    @State private var scenic: [Destination] = []
    @State private var scenicLoading = false
    @StateObject private var subscription = SubscriptionManager.shared
    @State private var showPaywall = false
    @AppStorage("routeNetworkEnabled") private var networkEnabled = false
    @AppStorage("routeProfile") private var routeProfile = RoutePreference.safety.rawValue

    private let locationManager = CLLocationManager()
    private let search = DestinationSearch()
    private let service = RouteService()
    private let loops = defaultLoopSuggestions()

    /// 默认落地态（无搜索、无已选路线）→ 展示推荐。
    private var showingRecommendations: Bool { plan == nil && results.isEmpty }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    TextField("搜索目的地", text: $query)
                        .onSubmit { Task { await runSearch() } }
                }

                if showingRecommendations {
                    Section("路线偏好") {
                        Picker("路线偏好", selection: $routeProfile) {
                            ForEach(RoutePreference.allCases) { pref in
                                Text(pref.label).tag(pref.rawValue)
                            }
                        }
                        .pickerStyle(.segmented)
                        if let pref = RoutePreference(rawValue: routeProfile) {
                            Label(pref.detail, systemImage: pref.icon)
                                .font(.footnote).foregroundStyle(.secondary)
                        }
                    }

                    Section("环形骑行路线") {
                        ForEach(loops) { loop in
                            Button {
                                Task { await planLoop(loop) }
                            } label: {
                                Label {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("约 \(Int(loop.targetKilometers)) 公里环线")
                                        Text("从当前位置出发，绕一圈回到起点")
                                            .font(.caption).foregroundStyle(.secondary)
                                    }
                                } icon: {
                                    Image(systemName: "arrow.triangle.capsulepath").foregroundStyle(.tint)
                                }
                            }
                        }
                    }

                    Section("附近风景目的地") {
                        if scenicLoading {
                            HStack(spacing: 8) {
                                ProgressView()
                                Text("正在找附近好去处…").font(.caption).foregroundStyle(.secondary)
                            }
                        } else if scenic.isEmpty {
                            Text("附近暂时没找到推荐目的地")
                                .font(.caption).foregroundStyle(.secondary)
                        } else {
                            ForEach(scenic) { dest in
                                Button {
                                    Task { await planRoute(to: dest) }
                                } label: {
                                    HStack {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(dest.name)
                                            if !dest.subtitle.isEmpty {
                                                Text(dest.subtitle).font(.caption)
                                                    .foregroundStyle(.secondary).lineLimit(1)
                                            }
                                        }
                                        Spacer()
                                        if let dist = distanceText(to: dest.coordinate) {
                                            Text(dist).font(.caption).foregroundStyle(.secondary)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                if let plan {
                    Section("路线") {
                        RoutePreviewMap(coordinates: plan.coordinates)
                            .frame(height: 220)
                            .listRowInsets(EdgeInsets())
                        LabeledContent("距离", value: String(format: "%.1f 公里", plan.distanceMeters / 1000))
                        LabeledContent("预计", value: "\(plan.estimatedMinutes) 分钟")
                        Label("已尽量避开主干道", systemImage: "leaf")
                            .font(.caption).foregroundStyle(.secondary)
                        if let dest = lastDestination {
                            NavigationLink {
                                RideNavigationView(plan: plan, destination: dest)
                            } label: {
                                Label("开始导航", systemImage: "location.north.line.fill")
                            }
                        }
                        Button(role: .cancel) {
                            self.plan = nil
                            lastDestination = nil
                            results = []
                        } label: {
                            Label("重新选择", systemImage: "chevron.left")
                        }
                    }
                }

                if let errorText {
                    Text(errorText).font(.caption).foregroundStyle(.red)
                }

                if !results.isEmpty {
                    Section("附近地点") {
                        ForEach(results) { dest in
                            Button {
                                Task { await planRoute(to: dest) }
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(dest.name)
                                    if !dest.subtitle.isEmpty {
                                        Text(dest.subtitle).font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("路线")
            .overlay { if loading { ProgressView() } }
            .sheet(isPresented: $showConsent) { consentSheet }
            .sheet(isPresented: $showPaywall) { PaywallView() }
            .onAppear { locationManager.requestWhenInUseAuthorization() }
            .task { await loadScenic() }
        }
    }

    private var consentSheet: some View {
        VStack(spacing: 16) {
            Image(systemName: "point.topleft.down.curvedto.point.bottomright.up")
                .font(.largeTitle).foregroundStyle(.tint)
            Text("路线规划需要联网").font(.headline)
            Text("规划路线会把你的起点与目的地坐标发送给地图路线服务（brouter.de），仅用于算路。")
                .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
            Button("同意并启用") {
                networkEnabled = true
                showConsent = false
            }
            .buttonStyle(.borderedProminent)
            Button("取消", role: .cancel) { showConsent = false }
        }
        .padding()
        .presentationDetents([.medium])
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
        guard subscription.isPro else { showPaywall = true; return }
        guard networkEnabled else { showConsent = true; return }
        guard let from = currentCoordinate() else { errorText = "无法获取当前位置"; return }
        loading = true
        errorText = nil
        let result = await service.route(from: from, to: dest.coordinate, profile: routeProfile)
        loading = false
        switch result {
        case .success(let p): plan = p; lastDestination = dest.coordinate
        case .failure(let e): errorText = message(for: e)
        }
    }

    /// 规划一条环线：当前位置出发，绕一圈回起点。
    private func planLoop(_ loop: LoopSuggestion) async {
        guard subscription.isPro else { showPaywall = true; return }
        guard networkEnabled else { showConsent = true; return }
        guard let from = currentCoordinate() else { errorText = "无法获取当前位置"; return }
        loading = true
        errorText = nil
        // 直线三角骨架沿路绕行后实际里程约为 1.4× 骨架长，故把骨架按系数缩小，
        // 让算出的真实环线更接近卡片标注的「约 X 公里」。
        let roadFactor = 0.72
        let waypoints = loopWaypoints(
            origin: from,
            targetMeters: loop.targetMeters * roadFactor,
            startBearingDegrees: loop.startBearingDegrees)
        let result = await service.route(through: waypoints, profile: routeProfile)
        loading = false
        switch result {
        case .success(let p): plan = p; lastDestination = from   // 环线终点=起点
        case .failure(let e): errorText = message(for: e)
        }
    }

    /// 进页面时加载附近风景目的地（等定位就绪，最多约 3 秒）。走 Apple 地图，无需联网同意。
    private func loadScenic() async {
        guard scenic.isEmpty, !scenicLoading else { return }
        scenicLoading = true
        defer { scenicLoading = false }
        var center = currentCoordinate()
        var tries = 0
        while center == nil && tries < 6 {
            try? await Task.sleep(for: .milliseconds(500))
            center = currentCoordinate()
            tries += 1
        }
        guard let center else { return }
        scenic = await search.nearbyScenic(near: center)
    }

    /// 当前位置到某坐标的直线距离文案（推荐目的地用）。
    private func distanceText(to coord: GeoCoordinate) -> String? {
        guard let from = currentCoordinate() else { return nil }
        let d = CLLocation(latitude: from.latitude, longitude: from.longitude)
            .distance(from: CLLocation(latitude: coord.latitude, longitude: coord.longitude))
        return d >= 1000 ? String(format: "%.1fkm", d / 1000) : String(format: "%.0fm", d)
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
        let coords = coordinates.map {
            CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude)
        }
        Map(initialPosition: .region(region(coords))) {
            if coords.count >= 2 {
                MapPolyline(coordinates: coords).stroke(.tint, lineWidth: 4)
            }
            if let s = coords.first { Marker("起点", coordinate: s).tint(.green) }
            if let e = coords.last { Marker("终点", coordinate: e).tint(.red) }
        }
    }

    private func region(_ coords: [CLLocationCoordinate2D]) -> MKCoordinateRegion {
        guard !coords.isEmpty else {
            return MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: 39.9, longitude: 116.4),
                span: MKCoordinateSpan(latitudeDelta: 0.1, longitudeDelta: 0.1))
        }
        let lats = coords.map(\.latitude), lons = coords.map(\.longitude)
        let center = CLLocationCoordinate2D(
            latitude: (lats.min()! + lats.max()!) / 2,
            longitude: (lons.min()! + lons.max()!) / 2)
        let span = MKCoordinateSpan(
            latitudeDelta: max(0.01, (lats.max()! - lats.min()!) * 1.4),
            longitudeDelta: max(0.01, (lons.max()! - lons.min()!) * 1.4))
        return MKCoordinateRegion(center: center, span: span)
    }
}
