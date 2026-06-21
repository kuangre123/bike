import SwiftUI
import MapKit
import SwiftData
import CyclingDomain

/// 单次运动详情：地图轨迹（有路线时）+ 数据。
struct RideDetailView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    let ride: RideModel
    @State private var showingDeleteConfirmation = false

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

            Section("数据") {
                row("类型", Formatters.activityLabel(type))
                row("开始", Formatters.fullDateTime(ride.startDate))
                row("时长", Formatters.duration(ride.duration))
                if let d = ride.distanceMeters { row(metricLabel("距离"), Formatters.distance(d)) }
                if let s = ride.avgSpeedMps { row(metricLabel("均速"), Formatters.speed(s)) }
                if let pace = Formatters.pace(duration: ride.duration, distanceMeters: ride.distanceMeters) {
                    row(metricLabel("配速"), pace)
                }
                if let maxSpeed = maxRouteSpeedMps { row("最高速度", Formatters.speed(maxSpeed)) }
                if let c = ride.calories { row(metricLabel("卡路里"), Formatters.calories(c)) }
                if ride.distanceMeters != nil { row("估算减碳", Formatters.carbonSaved(ride.distanceMeters)) }
                if let hr = Formatters.heartRate(ride.avgHeartRate) { row("均心率", hr) }
                row("来源", Formatters.sourceLabel(source))
            }

            if ride.isAutoDetected {
                Section {
                    Label(autoDetectedNote, systemImage: "sparkles")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle(Formatters.activityLabel(type))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(role: .destructive) {
                    showingDeleteConfirmation = true
                } label: {
                    Label("删除", systemImage: "trash")
                }
            }
        }
        .confirmationDialog("删除这次运动？", isPresented: $showingDeleteConfirmation, titleVisibility: .visible) {
            Button("删除", role: .destructive) {
                Task { await deleteRide() }
            }
            Button("取消", role: .cancel) {}
        }
    }

    private func row(_ key: String, _ value: String) -> some View {
        LabeledContent(key, value: value)
    }

    private func metricLabel(_ title: String) -> String {
        isEstimatedMetrics ? "估算\(title)" : title
    }

    private var autoDetectedNote: String {
        if isEstimatedMetrics {
            return "自动检测添加；无 GPS 路线，距离、均速和卡路里按运动历史估算"
        }
        return "自动检测添加"
    }

    private func deleteRide() async {
        if let uuid = ride.healthKitWorkoutUUID {
            let health = HealthService()
            _ = await health.requestWriteAuthorization()
            _ = await health.deleteWorkout(uuid: uuid)
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
