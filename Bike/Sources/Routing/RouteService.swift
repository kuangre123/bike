import Foundation
import CyclingDomain

enum RouteError: Error, Equatable {
    case networkDisabled
    case offline
    case noRoute
    case server
}

/// 调 BRouter 公共服务器算一条安静骑行路线。默认 `safety` 档：避开车多的主干道、
/// 优先住宅区小路与自行车道（比 trekking 更"小众安静"）。
struct RouteService {
    var baseURL = "https://brouter.de/brouter"
    var session: URLSession = .shared

    func route(
        from: GeoCoordinate, to: GeoCoordinate, profile: String = "safety"
    ) async -> Result<RoutePlan, RouteError> {
        await route(through: [from, to], profile: profile)
    }

    /// 经过多个航点算一条路线（环线推荐：起点→顶点→顶点→回起点）。
    func route(
        through waypoints: [GeoCoordinate], profile: String = "safety"
    ) async -> Result<RoutePlan, RouteError> {
        guard RoutePrefs.networkEnabled else { return .failure(.networkDisabled) }
        guard waypoints.count >= 2 else { return .failure(.noRoute) }
        // 与 BRouter(WGS-84) 通信前，把 Apple 的 GCJ-02 航点逐个转成 WGS-84
        let lonlats = waypoints
            .map(ChinaGeo.gcj02ToWgs84)
            .map { "\($0.longitude),\($0.latitude)" }
            .joined(separator: "|")
        var comps = URLComponents(string: baseURL)!
        comps.queryItems = [
            .init(name: "lonlats", value: lonlats),
            .init(name: "profile", value: profile),
            .init(name: "alternativeidx", value: "0"),
            .init(name: "format", value: "geojson"),
            // 要转向指令（voicehints）。几何推导在弯路上会把每个拐角当转弯，
            // 实测 9.2 km 山路 165 次 vs 引擎 27 次。
            .init(name: "timode", value: "3"),
        ]
        guard let url = comps.url else { return .failure(.server) }
        do {
            let (data, response) = try await session.data(from: url)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                return .failure(.server)
            }
            guard let plan = parseBRouterGeoJSON(data) else { return .failure(.noRoute) }
            // BRouter 返回 WGS-84，转回 GCJ-02 以便画在 Apple 地图上对齐（否则偏移穿楼）
            // BRouter 返回 WGS-84，转回 GCJ-02 以便画在 Apple 地图上对齐（否则偏移穿楼）。
            // 用 withCoordinates 而不是手工重建：以前手工重建只传了三个字段，把海拔和
            // 逐段路面全丢了，路况预警因此在 1.4 里从没工作过。
            let aligned = plan.withCoordinates(plan.coordinates.map(ChinaGeo.wgs84ToGcj02))
            return .success(aligned)
        } catch {
            return .failure(.offline)
        }
    }
}
