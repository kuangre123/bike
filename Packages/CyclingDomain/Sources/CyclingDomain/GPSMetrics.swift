import Foundation

/// 两点间 haversine 距离（米）。
public func haversineMeters(lat1: Double, lon1: Double, lat2: Double, lon2: Double) -> Double {
    let earthRadius = 6_371_000.0
    let dLat = (lat2 - lat1) * .pi / 180
    let dLon = (lon2 - lon1) * .pi / 180
    let a = sin(dLat / 2) * sin(dLat / 2)
        + cos(lat1 * .pi / 180) * cos(lat2 * .pi / 180)
        * sin(dLon / 2) * sin(dLon / 2)
    let c = 2 * atan2(sqrt(a), sqrt(1 - a))
    return earthRadius * c
}

/// 沿采样点累计的总距离（米）。少于 2 点返回 0。
public func totalDistanceMeters(_ samples: [GPSSample]) -> Double {
    guard samples.count >= 2 else { return 0 }
    var total = 0.0
    for i in 1..<samples.count {
        total += haversineMeters(
            lat1: samples[i - 1].latitude, lon1: samples[i - 1].longitude,
            lat2: samples[i].latitude,     lon2: samples[i].longitude
        )
    }
    return total
}

/// 均速 m/s。时长 <= 0 返回 0。
public func averageSpeedMps(distanceMeters: Double, duration: TimeInterval) -> Double {
    guard duration > 0 else { return 0 }
    return distanceMeters / duration
}
