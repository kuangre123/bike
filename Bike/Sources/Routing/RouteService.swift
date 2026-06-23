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
        // 与 BRouter(WGS-84) 通信前，把 Apple 的 GCJ-02 起终点转成 WGS-84
        let fromW = ChinaGeo.gcj02ToWgs84(from)
        let toW = ChinaGeo.gcj02ToWgs84(to)
        let lonlats = "\(fromW.longitude),\(fromW.latitude)|\(toW.longitude),\(toW.latitude)"
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
            // BRouter 返回 WGS-84，转回 GCJ-02 以便画在 Apple 地图上对齐（否则偏移穿楼）
            let aligned = RoutePlan(
                coordinates: plan.coordinates.map(ChinaGeo.wgs84ToGcj02),
                distanceMeters: plan.distanceMeters,
                estimatedSeconds: plan.estimatedSeconds)
            return .success(aligned)
        } catch {
            return .failure(.offline)
        }
    }
}
