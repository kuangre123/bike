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
    /// 每个坐标点的海拔（米），与 `coordinates` 一一对应。BRouter 没给就是空。
    public let elevations: [Double]
    /// 逐段路面 / 道路等级。BRouter 没给就是空。
    public let segments: [RouteSegment]
    /// BRouter 算好的累计爬升（它的 `filtered ascend`，做过噪声滤波）。
    /// 优先用它而不是我们自己把每点高差裸加——SRTM 抖动会让裸加系统性偏高
    /// （实测同一条路线：裸加 1307 m，BRouter 1173 m）。
    public let reportedAscentMeters: Double?
    /// 算路引擎给的转向指令（含末尾 `.arrive`）。BRouter 没返回时为空，
    /// 导航端退回几何推导 `turnsFromPolyline`。
    public let turns: [TurnInstruction]

    public init(
        coordinates: [GeoCoordinate],
        distanceMeters: Double,
        estimatedSeconds: Double,
        elevations: [Double] = [],
        segments: [RouteSegment] = [],
        reportedAscentMeters: Double? = nil,
        turns: [TurnInstruction] = []
    ) {
        self.coordinates = coordinates
        self.distanceMeters = distanceMeters
        self.estimatedSeconds = estimatedSeconds
        self.elevations = elevations
        self.segments = segments
        self.reportedAscentMeters = reportedAscentMeters
        self.turns = turns
    }

    /// 只换坐标（比如 WGS-84 → GCJ-02 对齐），其余字段原样保留。
    ///
    /// 海拔、逐段、转向都是按**下标**对应坐标的，坐标做等长变换后下标关系不变，
    /// 所以可以直接带过去。以前 RouteService 是手工重建 `RoutePlan`，只传了三个字段，
    /// 把海拔和逐段路面全丢了——路况预警在 1.4 里因此从没工作过。用这个就漏不掉。
    public func withCoordinates(_ newCoordinates: [GeoCoordinate]) -> RoutePlan {
        precondition(newCoordinates.count == coordinates.count,
                     "坐标变换必须等长，否则海拔/转向的下标会错位")
        return RoutePlan(
            coordinates: newCoordinates,
            distanceMeters: distanceMeters,
            estimatedSeconds: estimatedSeconds,
            elevations: elevations,
            segments: segments,
            reportedAscentMeters: reportedAscentMeters,
            turns: turns)
    }

    /// 导航用的转向列表：优先算路引擎的（只在真正的路口发提示），没有才几何推导。
    /// 「只有 .arrive」等于引擎没给转弯信息，也算没有。
    public var navigationTurns: [TurnInstruction] {
        turns.count > 1 ? turns : turnsFromPolyline(coordinates)
    }

    public var estimatedMinutes: Int { Int((estimatedSeconds / 60).rounded()) }

    /// 累计爬升（米）。没有海拔数据时为 nil——不是 0，是「不知道」。
    /// 优先用 BRouter 滤波后的值，没有才自己算。
    public var ascentMeters: Double? {
        if let reportedAscentMeters { return reportedAscentMeters }
        guard elevations.count >= 2 else { return nil }
        var gain = 0.0
        for i in 1..<elevations.count {
            let delta = elevations[i] - elevations[i - 1]
            if delta > 0 { gain += delta }
        }
        return gain
    }

    /// 出发前的路况预警，按距起点排序。
    public var warnings: [RouteWarning] {
        RouteAnalysis.warnings(coordinates: coordinates, elevations: elevations, segments: segments)
    }
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
