import SwiftUI
import MapKit
import SwiftData
import Charts
import StoreKit
import CyclingDomain

/// 单次运动详情：地图轨迹（有路线时）+ 数据。
struct RideDetailView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.requestReview) private var requestReview
    @Environment(\.openURL) private var openURL
    @Environment(PermissionsManager.self) private var permissions
    let ride: RideModel
    @State private var showingDeleteConfirmation = false
    @State private var shareItem: ShareableImage?
    @State private var isPreparingShareCard = false
    @State private var gpxFile: GPXFile?

    private var type: ActivityType { RideMapping.activityType(of: ride) }
    private var source: RideSource { RideMapping.source(of: ride) }
    private var isEstimatedMetrics: Bool { source == .motionOnly }
    private var routePoints: [RoutePointDTO] { RideMapping.decodeRoute(ride.routeData) }
    private var coords: [CLLocationCoordinate2D] {
        routePoints.map {
            CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude)
        }
    }
    private var maxRouteSpeedMps: Double? {
        routePoints
            .map(\.speedMps)
            .filter { $0 > 0 && $0 < 30 }
            .max()
    }
    /// 累计爬升（米）；轨迹无海拔（旧记录/无垂直定位）为 nil。
    private var elevationGain: Double? {
        let alts = routePoints.compactMap(\.altitude)
        guard alts.count >= 2 else { return nil }
        return elevationGainMeters(altitudes: alts)
    }
    /// 速度曲线数据点（分钟, km/h），降采样到 ≤120 点防长轨迹卡顿。
    private var speedCurve: [(minutes: Double, kmh: Double)] {
        let valid = routePoints.filter { $0.speedMps >= 0 && $0.speedMps < 30 }
        guard valid.count >= 5, let start = valid.first?.timestamp else { return [] }
        let stride = max(1, valid.count / 120)
        return valid.enumerated()
            .filter { $0.offset.isMultiple(of: stride) }
            .map { (minutes: $0.element.timestamp.timeIntervalSince(start) / 60,
                    kmh: $0.element.speedMps * 3.6) }
    }

    var body: some View {
        List {
            if !coords.isEmpty {
                Section {
                    Map(initialPosition: .region(region(for: coords))) {
                        MapPolyline(coordinates: coords).stroke(.tint, lineWidth: 4)
                        if let s = coords.first {
                            Marker("起点", systemImage: "flag", coordinate: s).tint(.green)
                        }
                        if let e = coords.last {
                            Marker("终点", systemImage: "flag.checkered", coordinate: e).tint(.red)
                        }
                    }
                    .frame(height: 240)
                    .listRowInsets(EdgeInsets())
                }
            }

            if !speedCurve.isEmpty {
                Section("速度曲线") {
                    Chart(speedCurve, id: \.minutes) { point in
                        AreaMark(
                            x: .value("分钟", point.minutes),
                            y: .value("速度", point.kmh)
                        )
                        .foregroundStyle(
                            LinearGradient(
                                colors: [Color(red: 0.05, green: 0.64, blue: 0.86).opacity(0.32), .clear],
                                startPoint: .top, endPoint: .bottom
                            )
                        )
                        LineMark(
                            x: .value("分钟", point.minutes),
                            y: .value("速度", point.kmh)
                        )
                        .foregroundStyle(Color(red: 0.05, green: 0.64, blue: 0.86))
                        .interpolationMethod(.monotone)
                    }
                    .chartXAxis {
                        AxisMarks { value in
                            AxisGridLine()
                            AxisValueLabel {
                                if let m = value.as(Double.self) {
                                    Text("\(Int(m))分").font(.caption2)
                                }
                            }
                        }
                    }
                    .chartYAxis {
                        AxisMarks { value in
                            AxisGridLine()
                            AxisValueLabel {
                                if let v = value.as(Double.self) {
                                    Text("\(Int(v))").font(.caption2)
                                }
                            }
                        }
                    }
                    .frame(height: 150)
                    .padding(.vertical, 4)
                }
            }

            Section("数据") {
                row("类型", Formatters.activityLabel(type))
                row("开始", Formatters.fullDateTime(ride.startDate))
                row("时长", Formatters.duration(ride.duration))
                if let d = ride.distanceMeters { row(isEstimatedMetrics ? "估算距离" : "距离", Formatters.distance(d)) }
                if let s = ride.avgSpeedMps { row(isEstimatedMetrics ? "估算均速" : "均速", Formatters.speed(s)) }
                if let pace = Formatters.pace(duration: ride.duration, distanceMeters: ride.distanceMeters) {
                    row(isEstimatedMetrics ? "估算配速" : "配速", pace)
                }
                if let maxSpeed = maxRouteSpeedMps { row("最高速度", Formatters.speed(maxSpeed)) }
                if let gain = elevationGain, gain >= 1 { row("累计爬升", String(localized: "\(Int(gain.rounded())) 米")) }
                if let c = ride.calories { row(isEstimatedMetrics ? "估算卡路里" : "卡路里", Formatters.calories(c)) }
                if ride.distanceMeters != nil { row("估算减碳", Formatters.carbonSaved(ride.distanceMeters)) }
                if let hr = Formatters.heartRate(ride.avgHeartRate) { row("均心率", hr) }
                // 导入记录显示真实来源名（如「Garmin Connect」），比笼统的「外部设备」有用。
                row("来源", ride.externalSourceName ?? Formatters.sourceLabel(source))
            }

            if ride.isAutoDetected {
                Section {
                    Label(autoDetectedNote, systemImage: "sparkles")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    // 没轨迹又不是「始终」定位时，八成就是这个原因。只在这条记录
                    // 确实缺轨迹时才提示，不是逮着人就催权限。
                    if coords.isEmpty, permissions.needsAlwaysForRouteRecording {
                        Button {
                            openURL(URL(string: UIApplication.openSettingsURLString)!)
                        } label: {
                            Label(
                                "定位权限目前不是「始终」，App 无法在后台记录路线。改成「始终」后，之后的骑行会自动画出轨迹。",
                                systemImage: "location.slash"
                            )
                            .font(.caption)
                        }
                    }
                }
            }

            if ride.excludedAsEBike {
                Section {
                    Button {
                        Task { await EBikeFlagging.restore(ride, context: context) }
                    } label: {
                        Label("恢复此记录", systemImage: "arrow.uturn.backward")
                    }
                } footer: {
                    Text("已排除（电动车）：不计入统计。恢复后重新计入，并按设置写回 Apple 健康。")
                }
            } else if type == .cycling {
                Section {
                    if EBikeFlagging.showsBadge(for: ride) {
                        Label("疑似电动车：长时间高速且速度几乎不变", systemImage: "bolt.fill")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                    Button {
                        Task { await EBikeFlagging.exclude(ride, context: context) }
                    } label: {
                        Label("标为电动车并排除", systemImage: "bolt.slash")
                    }
                    .foregroundStyle(.orange)
                } footer: {
                    Text("排除后不计入统计；若已写入 Apple 健康会一并删除。可随时恢复。")
                }
            }
        }
        .navigationTitle(Formatters.activityLabel(type))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        // 地图底图要下载瓦片，慢的话给个转圈，别让人以为按钮没反应。
                        isPreparingShareCard = true
                        Task {
                            let image = await RideShareCard.renderImage(for: ride)
                            isPreparingShareCard = false
                            if let image { shareItem = ShareableImage(image: image) }
                        }
                    } label: {
                        Label("分享卡片", systemImage: "photo")
                    }
                    if !routePoints.isEmpty {
                        Button(action: exportGPX) {
                            Label("导出 GPX 轨迹", systemImage: "point.topleft.down.curvedto.point.bottomright.up")
                        }
                    }
                } label: {
                    Label("分享", systemImage: "square.and.arrow.up")
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button(role: .destructive) {
                    showingDeleteConfirmation = true
                } label: {
                    Label("删除", systemImage: "trash")
                }
            }
        }
        .overlay {
            if isPreparingShareCard {
                ProgressView("正在生成分享卡片…")
                    .padding(20)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
            }
        }
        .sheet(item: $shareItem) { item in
            ShareImageSheet(image: item.image)
                .presentationDetents([.medium, .large])
        }
        .sheet(item: $gpxFile) { item in
            ShareFileSheet(url: item.url)
        }
        .onChange(of: shareItem) { old, new in
            // 价值时刻③：分享完卡片（分享面板收起）——最强好感信号。
            guard old != nil, new == nil else { return }
            let total = (try? context.fetchCount(FetchDescriptor<RideModel>())) ?? 0
            if ReviewPrompt.registerPositiveMomentAndDecide(totalRides: total) {
                requestReview()
            }
        }
        .confirmationDialog("删除这次运动？", isPresented: $showingDeleteConfirmation, titleVisibility: .visible) {
            Button("删除", role: .destructive) {
                Task { await deleteRide() }
            }
            Button("取消", role: .cancel) {}
        }
    }

    /// key 用 LocalizedStringKey（字面量→走目录本地化）；value 已由 Formatters 本地化，逐字显示。
    private func row(_ key: LocalizedStringKey, _ value: String) -> some View {
        LabeledContent(key) { Text(value) }
    }

    private var autoDetectedNote: String {
        if isEstimatedMetrics {
            return String(localized: "自动检测添加；无 GPS 路线，距离、均速和卡路里按运动历史估算")
        }
        return String(localized: "自动检测添加")
    }

    /// 导出当前骑行为 GPX，写入临时文件并弹分享面板。无轨迹则忽略。
    private func exportGPX() {
        let samples = RideMapping.gpsSamples(ride.routeData)
        guard !samples.isEmpty else { return }
        let name = "\(Formatters.activityLabel(type)) \(Formatters.fullDateTime(ride.startDate))"
        let xml = gpxDocument(trackName: name, points: samples)

        let stamp = DateFormatter()
        stamp.dateFormat = "yyyyMMdd-HHmm"
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("HappyRide-\(stamp.string(from: ride.startDate)).gpx")
        do {
            try xml.data(using: .utf8)?.write(to: fileURL, options: .atomic)
            gpxFile = GPXFile(url: fileURL)
        } catch {
            // 写入失败静默忽略——不影响其它功能。
        }
    }

    private func deleteRide() async {
        // 只删本 app 写进健康的那条。导入记录的 workout 是对方写的，不归我们删——
        // 改为记个墓碑，下次导入不再把它搬回来。
        if let uuid = ride.healthKitWorkoutUUID {
            let health = HealthService()
            _ = await health.requestWriteAuthorization()
            _ = await health.deleteWorkout(uuid: uuid)
        }
        if let external = ride.externalWorkoutUUID {
            ExternalSourcePreferences.dismiss(external)
        }
        context.delete(ride)
        try? context.save()
        dismiss()
    }

    /// 计算覆盖整条轨迹的地图区域（留 40% 边距）。
    private func region(for coords: [CLLocationCoordinate2D]) -> MKCoordinateRegion {
        let lats = coords.map(\.latitude)
        let lons = coords.map(\.longitude)
        let minLat = lats.min()!, maxLat = lats.max()!
        let minLon = lons.min()!, maxLon = lons.max()!
        let center = CLLocationCoordinate2D(latitude: (minLat + maxLat) / 2, longitude: (minLon + maxLon) / 2)
        let span = MKCoordinateSpan(
            latitudeDelta: max(0.005, (maxLat - minLat) * 1.4),
            longitudeDelta: max(0.005, (maxLon - minLon) * 1.4)
        )
        return MKCoordinateRegion(center: center, span: span)
    }
}

/// `.sheet(item:)` 用的 GPX 文件包装。
private struct GPXFile: Identifiable {
    let id = UUID()
    let url: URL
}
