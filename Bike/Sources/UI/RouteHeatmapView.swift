import SwiftUI
import MapKit

/// 「骑行足迹」：把所有骑行轨迹叠加到一张地图。半透明描边——重叠越多的路段越浓，
/// 形成伪热力效果。免费功能。长轨迹逐条降采样到 ≤200 点防卡顿。
struct RouteHeatmapView: View {
    let rides: [RideModel]

    /// 每条未排除记录的坐标序列（已降采样，过滤空轨迹）。
    private var routes: [[CLLocationCoordinate2D]] {
        rides
            .filter { !$0.excludedAsEBike }
            .compactMap { ride -> [CLLocationCoordinate2D]? in
                let pts = RideMapping.decodeRoute(ride.routeData)
                guard pts.count >= 2 else { return nil }
                let step = max(1, pts.count / 200)
                let sampled = pts.enumerated().filter { $0.offset.isMultiple(of: step) }.map(\.element)
                return sampled.map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) }
            }
    }

    private var allCoords: [CLLocationCoordinate2D] { routes.flatMap { $0 } }

    private var totalKm: Double {
        rides.filter { !$0.excludedAsEBike }.reduce(0.0) { $0 + ($1.distanceMeters ?? 0) } / 1000
    }

    var body: some View {
        Group {
            if routes.isEmpty {
                emptyState
            } else {
                Map(initialPosition: .region(boundingRegion(allCoords))) {
                    ForEach(Array(routes.enumerated()), id: \.offset) { _, coords in
                        MapPolyline(coordinates: coords)
                            .stroke(Color(red: 0.95, green: 0.30, blue: 0.10).opacity(0.28), lineWidth: 4)
                    }
                }
                .safeAreaInset(edge: .bottom) { footprintBar }
            }
        }
        .navigationTitle("骑行足迹")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var footprintBar: some View {
        HStack(spacing: 16) {
            stat("\(routes.count)", "条轨迹")
            Divider().frame(height: 28)
            stat(String(format: "%.0f", totalKm), "公里足迹")
        }
        .padding(.horizontal, 18).padding(.vertical, 10)
        .background(.ultraThinMaterial)
        .clipShape(Capsule())
        .overlay(Capsule().stroke(Color.white.opacity(0.5), lineWidth: 1))
        .shadow(color: .black.opacity(0.12), radius: 10, y: 4)
        .padding(.bottom, 16)
    }

    private func stat(_ value: String, _ title: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.headline.weight(.heavy)).foregroundStyle(.primary)
            Text(title).font(.caption2).foregroundStyle(.secondary)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "map")
                .font(.system(size: 34, weight: .bold))
                .foregroundStyle(Color(red: 0.95, green: 0.30, blue: 0.10))
            Text("还没有带轨迹的骑行").font(.headline)
            Text("有 GPS 轨迹的骑行会在这里连成你的足迹地图。")
                .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .padding(40)
    }

    /// 覆盖所有坐标的地图区域（留 30% 边距）。
    private func boundingRegion(_ coords: [CLLocationCoordinate2D]) -> MKCoordinateRegion {
        guard !coords.isEmpty else {
            return MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: 31.23, longitude: 121.47),
                                      span: MKCoordinateSpan(latitudeDelta: 0.1, longitudeDelta: 0.1))
        }
        let lats = coords.map(\.latitude), lons = coords.map(\.longitude)
        let minLat = lats.min()!, maxLat = lats.max()!, minLon = lons.min()!, maxLon = lons.max()!
        let center = CLLocationCoordinate2D(latitude: (minLat + maxLat) / 2, longitude: (minLon + maxLon) / 2)
        let span = MKCoordinateSpan(
            latitudeDelta: max(0.01, (maxLat - minLat) * 1.3),
            longitudeDelta: max(0.01, (maxLon - minLon) * 1.3))
        return MKCoordinateRegion(center: center, span: span)
    }
}
