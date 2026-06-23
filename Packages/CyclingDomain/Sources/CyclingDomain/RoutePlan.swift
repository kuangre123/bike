import Foundation

/// 轻量地理坐标（路线用；不带时间/速度，区别于 GPSSample）。
public struct GeoCoordinate: Equatable, Sendable {
    public let latitude: Double
    public let longitude: Double
    public init(latitude: Double, longitude: Double) {
        self.latitude = latitude
        self.longitude = longitude
    }
}

/// 一条算好的骑行路线。
public struct RoutePlan: Equatable, Sendable {
    public let coordinates: [GeoCoordinate]
    public let distanceMeters: Double
    public let estimatedSeconds: Double
    public init(coordinates: [GeoCoordinate], distanceMeters: Double, estimatedSeconds: Double) {
        self.coordinates = coordinates
        self.distanceMeters = distanceMeters
        self.estimatedSeconds = estimatedSeconds
    }
    public var estimatedMinutes: Int { Int((estimatedSeconds / 60).rounded()) }
}

/// 折线累计长度（米），复用 haversine。
public func polylineLengthMeters(_ coords: [GeoCoordinate]) -> Double {
    guard coords.count >= 2 else { return 0 }
    var total = 0.0
    for i in 1..<coords.count {
        total += haversineMeters(
            lat1: coords[i - 1].latitude, lon1: coords[i - 1].longitude,
            lat2: coords[i].latitude, lon2: coords[i].longitude)
    }
    return total
}
