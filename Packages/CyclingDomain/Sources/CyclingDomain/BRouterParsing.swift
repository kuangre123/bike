import Foundation

/// 解析 BRouter 的 GeoJSON 响应为 RoutePlan。失败返回 nil。
/// 距离取 properties.track-length（米，字符串）；缺失则用折线长度兜底。
///
/// 坐标是三维的 `[经度, 纬度, 海拔]`，`properties.messages` 里还有逐段的 OSM 标签
/// （`surface`、`highway`、`cycleway:*`）。这些都在同一个响应里，不用额外请求。
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

    // 海拔要么每个点都有，要么当作没有——只有一部分点有海拔时，
    // 拿它算坡度会把缺口当成断崖。
    let elevations = rawCoords.compactMap { $0.count >= 3 ? $0[2] : nil }
    let alignedElevations = elevations.count == coordinates.count ? elevations : []

    let props = feature["properties"] as? [String: Any]
    let distance = (props?["track-length"] as? String).flatMap(Double.init)
        ?? polylineLengthMeters(coordinates)
    let seconds = (props?["total-time"] as? String).flatMap(Double.init) ?? 0

    return RoutePlan(
        coordinates: coordinates,
        distanceMeters: distance,
        estimatedSeconds: seconds,
        elevations: alignedElevations,
        segments: parseBRouterSegments(props?["messages"]),
        // BRouter 的 key 里真的带空格，不是笔误
        reportedAscentMeters: (props?["filtered ascend"] as? String).flatMap(Double.init),
        // 请求带 timode=3 才有；没带就是空数组 → 只剩 .arrive → navigationTurns 退回几何推导
        turns: props?["voicehints"] == nil ? [] : parseBRouterVoiceHints(props?["voicehints"], coordinates: coordinates)
    )
}

/// 解析 `properties.messages`：第一行是表头，其余每行是一段路。
///
/// 只认表头里的 `Distance` 和 `WayTags` 两列，按名字取而不是按固定下标——
/// BRouter 加列时不至于把整个解析弄错位。
public func parseBRouterSegments(_ raw: Any?) -> [RouteSegment] {
    guard let rows = raw as? [[String]], rows.count >= 2 else { return [] }
    let header = rows[0]
    guard let distanceColumn = header.firstIndex(of: "Distance"),
          let tagsColumn = header.firstIndex(of: "WayTags") else { return [] }

    var segments: [RouteSegment] = []
    var cumulative = 0.0
    for row in rows.dropFirst() {
        guard row.count > max(distanceColumn, tagsColumn),
              let length = Double(row[distanceColumn]) else { continue }
        segments.append(
            RouteSegment(
                startDistanceMeters: cumulative,
                lengthMeters: length,
                tags: RouteTerrain.parseTags(row[tagsColumn])
            )
        )
        cumulative += length
    }
    return segments
}
