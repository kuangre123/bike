import SwiftUI
import MapKit
import CyclingDomain

/// 单次运动详情：地图轨迹（有路线时）+ 数据。
struct RideDetailView: View {
    let ride: RideModel

    private var type: ActivityType { RideMapping.activityType(of: ride) }
    private var coords: [CLLocationCoordinate2D] {
        RideMapping.decodeRoute(ride.routeData).map {
            CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude)
        }
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
                if let d = ride.distanceMeters { row("距离", Formatters.distance(d)) }
                if let s = ride.avgSpeedMps { row("均速", Formatters.speed(s)) }
                if let c = ride.calories { row("卡路里", Formatters.calories(c)) }
                if let hr = ride.avgHeartRate { row("均心率", "\(Int(hr.rounded())) bpm") }
                row("来源", Formatters.sourceLabel(RideMapping.source(of: ride)))
            }

            if ride.isAutoDetected {
                Section {
                    Label("被动自动检测添加", systemImage: "sparkles")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle(Formatters.activityLabel(type))
        .navigationBarTitleDisplayMode(.inline)
    }

    private func row(_ key: String, _ value: String) -> some View {
        LabeledContent(key, value: value)
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
