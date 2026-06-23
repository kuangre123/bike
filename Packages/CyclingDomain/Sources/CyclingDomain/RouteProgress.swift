import Foundation

public struct NearestResult: Equatable, Sendable {
    public let segmentIndex: Int
    public let distanceMeters: Double
    public let projection: GeoCoordinate
}

/// 把点投影到折线，返回最近段、垂距（米）、投影点。局部等距平面近似（小范围足够准）。
public func nearestPointOnRoute(_ p: GeoCoordinate, _ coords: [GeoCoordinate]) -> NearestResult {
    precondition(coords.count >= 2)
    let mLatToM = 111_320.0
    let mLonToM = 111_320.0 * cos(p.latitude * .pi / 180)
    func xy(_ c: GeoCoordinate) -> (Double, Double) {
        ((c.longitude - p.longitude) * mLonToM, (c.latitude - p.latitude) * mLatToM)
    }
    var best = NearestResult(segmentIndex: 0, distanceMeters: .infinity, projection: coords[0])
    for i in 0..<(coords.count - 1) {
        let (ax, ay) = xy(coords[i])
        let (bx, by) = xy(coords[i + 1])
        let dx = bx - ax, dy = by - ay
        let len2 = dx * dx + dy * dy
        let t = len2 > 0 ? max(0, min(1, -(ax * dx + ay * dy) / len2)) : 0
        let px = ax + t * dx, py = ay + t * dy
        let dist = (px * px + py * py).squareRoot()
        if dist < best.distanceMeters {
            let proj = GeoCoordinate(
                latitude: p.latitude + py / mLatToM,
                longitude: p.longitude + px / mLonToM)
            best = NearestResult(segmentIndex: i, distanceMeters: dist, projection: proj)
        }
    }
    return best
}

/// 偏航判定（默认阈值 40m）。
public func isOffRoute(distanceToRouteMeters: Double, threshold: Double = 40) -> Bool {
    distanceToRouteMeters > threshold
}

public struct NavProgress: Equatable, Sendable {
    public let segmentIndex: Int
    public let distanceToRouteMeters: Double
    public let isOffRoute: Bool
    public let nextTurn: TurnInstruction?
    public let distanceToNextTurnMeters: Double
}

/// 综合：最近点 + 下一转向 + 到下一转向距离 + 偏航。
public func navigationProgress(
    location: GeoCoordinate, coords: [GeoCoordinate], turns: [TurnInstruction]
) -> NavProgress {
    let near = nearestPointOnRoute(location, coords)
    let off = isOffRoute(distanceToRouteMeters: near.distanceMeters)

    let next = turns.first { $0.coordinateIndex > near.segmentIndex }
    var distToTurn = 0.0
    if let next {
        distToTurn += haversineMeters(
            lat1: near.projection.latitude, lon1: near.projection.longitude,
            lat2: coords[near.segmentIndex + 1].latitude, lon2: coords[near.segmentIndex + 1].longitude)
        var i = near.segmentIndex + 1
        while i < next.coordinateIndex {
            distToTurn += haversineMeters(
                lat1: coords[i].latitude, lon1: coords[i].longitude,
                lat2: coords[i + 1].latitude, lon2: coords[i + 1].longitude)
            i += 1
        }
    }
    return NavProgress(
        segmentIndex: near.segmentIndex,
        distanceToRouteMeters: near.distanceMeters,
        isOffRoute: off,
        nextTurn: next,
        distanceToNextTurnMeters: distToTurn)
}
