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
