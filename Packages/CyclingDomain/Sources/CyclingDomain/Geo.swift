import Foundation

/// 两点初始航向（0..360，正北=0，顺时针）。
public func bearingDegrees(from a: GeoCoordinate, to b: GeoCoordinate) -> Double {
    let lat1 = a.latitude * .pi / 180, lat2 = b.latitude * .pi / 180
    let dLon = (b.longitude - a.longitude) * .pi / 180
    let y = sin(dLon) * cos(lat2)
    let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon)
    let deg = atan2(y, x) * 180 / .pi
    return (deg + 360).truncatingRemainder(dividingBy: 360)
}

/// 转向角（-180..180）：正=右转，负=左转。
public func signedTurnDegrees(incoming: Double, outgoing: Double) -> Double {
    var d = (outgoing - incoming).truncatingRemainder(dividingBy: 360)
    if d > 180 { d -= 360 }
    if d < -180 { d += 360 }
    return d
}

/// 从 origin 出发，按航向(度，正北=0 顺时针)走 distanceMeters 米后的目标点（球面大圆，R=6371km）。
public func destination(from origin: GeoCoordinate, bearingDegrees: Double, distanceMeters: Double) -> GeoCoordinate {
    let R = 6_371_000.0
    let d = distanceMeters / R
    let brng = bearingDegrees * .pi / 180
    let lat1 = origin.latitude * .pi / 180
    let lon1 = origin.longitude * .pi / 180
    let lat2 = asin(sin(lat1) * cos(d) + cos(lat1) * sin(d) * cos(brng))
    let lon2 = lon1 + atan2(sin(brng) * sin(d) * cos(lat1), cos(d) - sin(lat1) * sin(lat2))
    return GeoCoordinate(latitude: lat2 * 180 / .pi, longitude: lon2 * 180 / .pi)
}
