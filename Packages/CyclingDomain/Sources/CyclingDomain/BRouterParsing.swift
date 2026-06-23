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
