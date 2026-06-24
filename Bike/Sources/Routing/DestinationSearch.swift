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

    /// 附近风景目的地：跑几个关键词 → 合并去重 → 按到 center 距离排序 → 取前 limit。
    /// 过滤掉太近(<400m，骑过去没意思)与太远(>20km)的点。走 Apple 地图搜索，不联 BRouter，无需联网同意。
    func nearbyScenic(near center: GeoCoordinate, limit: Int = 6) async -> [Destination] {
        let queries = ["公园", "绿道", "湖", "河滨公园"]
        let here = CLLocation(latitude: center.latitude, longitude: center.longitude)
        var seen: Set<String> = []
        var collected: [(dest: Destination, dist: CLLocationDistance)] = []
        for q in queries {
            for dest in await search(q, near: center) {
                let key = String(format: "%.3f,%.3f", dest.coordinate.latitude, dest.coordinate.longitude)
                guard !seen.contains(key) else { continue }
                seen.insert(key)
                let d = here.distance(from: CLLocation(
                    latitude: dest.coordinate.latitude, longitude: dest.coordinate.longitude))
                guard d > 400, d < 20_000 else { continue }
                collected.append((dest, d))
            }
        }
        return collected.sorted { $0.dist < $1.dist }.prefix(limit).map(\.dest)
    }
}
