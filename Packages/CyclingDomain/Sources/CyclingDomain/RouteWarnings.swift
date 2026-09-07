import Foundation

/// 出发前能提前告诉用户的路况问题。
public enum RouteWarningKind: Equatable, Sendable {
    /// 持续爬坡，百分比为平均坡度。
    case steepClimb(percent: Double)
    /// 持续下坡（陡下坡对骑行同样是风险）。
    case steepDescent(percent: Double)
    /// 非铺装路面，带 OSM 原始 `surface` 值。
    case unpaved(surface: String)
    /// 车多且没有自行车道的路段。
    case busyRoad(highway: String)
    /// 行人道路 / 台阶：骑不过去，得推车。
    case footOnly(highway: String)
}

/// 一条路况预警，定位到「距起点多远、持续多长」。
public struct RouteWarning: Equatable, Sendable, Identifiable {
    public let kind: RouteWarningKind
    public let startDistanceMeters: Double
    public let lengthMeters: Double

    public init(kind: RouteWarningKind, startDistanceMeters: Double, lengthMeters: Double) {
        self.kind = kind
        self.startDistanceMeters = startDistanceMeters
        self.lengthMeters = lengthMeters
    }

    public var id: String { "\(kind)-\(Int(startDistanceMeters))" }
    public var endDistanceMeters: Double { startDistanceMeters + lengthMeters }
}

/// 从路线数据里挑出值得提前提醒的路段。纯函数。
public enum RouteAnalysis {

    /// 坡度至少要在这么长的距离上算才有意义。
    ///
    /// BRouter 的海拔来自 SRTM，约 30 米分辨率。在比这更短的距离上算坡度，
    /// 得到的是采样噪声不是坡——宁可不报，也不要报一个编出来的「12.3% 陡坡」。
    public static let minimumGradientBaseMeters: Double = 100

    /// 达到这个平均坡度才算「陡」。
    public static let steepGradientPercent: Double = 6

    /// 短于这个长度的路面变化不提示，否则一条路能报出几十条没用的提醒。
    public static let minimumSurfaceRunMeters: Double = 50

    /// 全部预警，按距起点由近到远排列。
    public static func warnings(
        coordinates: [GeoCoordinate],
        elevations: [Double],
        segments: [RouteSegment]
    ) -> [RouteWarning] {
        (climbWarnings(coordinates: coordinates, elevations: elevations)
            + surfaceWarnings(segments)
            + busyRoadWarnings(segments)
            + footOnlyWarnings(segments))
            .sorted { $0.startDistanceMeters < $1.startDistanceMeters }
    }

    // MARK: - 坡度

    /// 按至少 `minimumGradientBaseMeters` 的窗口切开算平均坡度，超过阈值的窗口合并成一条。
    ///
    /// 海拔数组必须和坐标一一对应；对不上就返回空——数据不完整时不猜。
    public static func climbWarnings(
        coordinates: [GeoCoordinate],
        elevations: [Double]
    ) -> [RouteWarning] {
        guard coordinates.count >= 2, coordinates.count == elevations.count else { return [] }

        var windows: [(start: Double, length: Double, percent: Double)] = []
        var windowStartDistance = 0.0
        var windowStartIndex = 0
        var cumulative = 0.0

        for i in 1..<coordinates.count {
            cumulative += haversineMeters(
                lat1: coordinates[i - 1].latitude, lon1: coordinates[i - 1].longitude,
                lat2: coordinates[i].latitude, lon2: coordinates[i].longitude)
            let run = cumulative - windowStartDistance
            guard run >= minimumGradientBaseMeters else { continue }
            let rise = elevations[i] - elevations[windowStartIndex]
            windows.append((windowStartDistance, run, rise / run * 100))
            windowStartDistance = cumulative
            windowStartIndex = i
        }
        // 末尾不足一个窗口的余量丢掉：不够长就算不出可信的坡度。

        return mergeAdjacent(windows.filter { abs($0.percent) >= steepGradientPercent }) { merged in
            merged.percent > 0
                ? .steepClimb(percent: merged.percent)
                : .steepDescent(percent: abs(merged.percent))
        }
    }

    /// 相邻且同向（都上坡或都下坡）的窗口合并，坡度按长度加权平均。
    private static func mergeAdjacent(
        _ windows: [(start: Double, length: Double, percent: Double)],
        kind: ((start: Double, length: Double, percent: Double)) -> RouteWarningKind
    ) -> [RouteWarning] {
        var result: [RouteWarning] = []
        var current: (start: Double, length: Double, percent: Double)?

        for window in windows {
            guard var running = current else { current = window; continue }
            let isContiguous = abs(running.start + running.length - window.start) < 1
            let sameDirection = (running.percent > 0) == (window.percent > 0)
            if isContiguous && sameDirection {
                let total = running.length + window.length
                running.percent =
                    (running.percent * running.length + window.percent * window.length) / total
                running.length = total
                current = running
            } else {
                result.append(RouteWarning(
                    kind: kind(running), startDistanceMeters: running.start, lengthMeters: running.length))
                current = window
            }
        }
        if let running = current {
            result.append(RouteWarning(
                kind: kind(running), startDistanceMeters: running.start, lengthMeters: running.length))
        }
        return result
    }

    // MARK: - 路面 / 道路等级

    /// 连续的非铺装路段合并成一条。`surface` 判不出来（缺标签）的不报。
    public static func surfaceWarnings(_ segments: [RouteSegment]) -> [RouteWarning] {
        runs(in: segments, where: { $0.isPaved == false })
            .map { run in
                RouteWarning(
                    kind: .unpaved(surface: run.sample.surface ?? "unpaved"),
                    startDistanceMeters: run.start,
                    lengthMeters: run.length)
            }
    }

    /// 车多且**没有自行车道**的路段。有自行车道就不算危险，不提示。
    public static func busyRoadWarnings(_ segments: [RouteSegment]) -> [RouteWarning] {
        runs(in: segments, where: { segment in
            guard let highway = segment.highway else { return false }
            return RouteTerrain.busyHighways.contains(highway) && !segment.hasCycleway
        })
        .map { run in
            RouteWarning(
                kind: .busyRoad(highway: run.sample.highway ?? "primary"),
                startDistanceMeters: run.start,
                lengthMeters: run.length)
        }
    }

    /// 只能推车通过的路段（步道、台阶）。算路引擎有时会为了抄近路串进来一小段。
    public static func footOnlyWarnings(_ segments: [RouteSegment]) -> [RouteWarning] {
        runs(in: segments, where: { segment in
            guard let highway = segment.highway else { return false }
            return RouteTerrain.footOnlyHighways.contains(highway)
        })
        .map { run in
            RouteWarning(
                kind: .footOnly(highway: run.sample.highway ?? "footway"),
                startDistanceMeters: run.start,
                lengthMeters: run.length)
        }
    }

    /// 把连续满足条件的段并成一串，短于 `minimumSurfaceRunMeters` 的丢掉。
    private static func runs(
        in segments: [RouteSegment],
        where matches: (RouteSegment) -> Bool
    ) -> [(start: Double, length: Double, sample: RouteSegment)] {
        var result: [(start: Double, length: Double, sample: RouteSegment)] = []
        var current: (start: Double, length: Double, sample: RouteSegment)?

        for segment in segments {
            if matches(segment) {
                if var running = current {
                    running.length += segment.lengthMeters
                    current = running
                } else {
                    current = (segment.startDistanceMeters, segment.lengthMeters, segment)
                }
            } else if let running = current {
                result.append(running)
                current = nil
            }
        }
        if let running = current { result.append(running) }
        return result.filter { $0.length >= minimumSurfaceRunMeters }
    }
}
