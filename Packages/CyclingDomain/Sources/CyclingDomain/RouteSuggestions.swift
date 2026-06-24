import Foundation

/// 一条「环形骑行路线」推荐：目标周长 + 给路由引擎的航点骨架（起点→两顶点→回起点）。
public struct LoopSuggestion: Equatable, Sendable, Identifiable {
    public let id: Int
    public let targetMeters: Double
    public let startBearingDegrees: Double
    public init(id: Int, targetMeters: Double, startBearingDegrees: Double) {
        self.id = id
        self.targetMeters = targetMeters
        self.startBearingDegrees = startBearingDegrees
    }

    public var targetKilometers: Double { targetMeters / 1000 }
}

/// 以 origin 为一个顶点，构造一条目标周长约 targetMeters 的等边三角形环线航点。
///
/// 等边三角形周长 = 3·边长，故边长 s = target/3；从 origin 出发两条边夹角 60°：
/// P1 在航向 θ、P2 在航向 θ+60°，各距 origin 为 s，则 |P1P2| 也 = s（等边）。
/// 返回 `[origin, P1, P2, origin]` 交给 BRouter 串成环。注意：实际沿路绕行会比这条
/// 直线骨架更长，所以 target 只是「意图距离」，卡片上应展示路由返回的真实里程。
public func loopWaypoints(origin: GeoCoordinate, targetMeters: Double, startBearingDegrees: Double) -> [GeoCoordinate] {
    let s = max(0, targetMeters) / 3
    let p1 = destination(from: origin, bearingDegrees: startBearingDegrees, distanceMeters: s)
    let p2 = destination(from: origin, bearingDegrees: startBearingDegrees + 60, distanceMeters: s)
    return [origin, p1, p2, origin]
}

/// 默认推荐的 3 条环线（约 5/10/20km），起始方向各异以求多样。
public func defaultLoopSuggestions() -> [LoopSuggestion] {
    [
        LoopSuggestion(id: 0, targetMeters: 5_000, startBearingDegrees: 30),
        LoopSuggestion(id: 1, targetMeters: 10_000, startBearingDegrees: 150),
        LoopSuggestion(id: 2, targetMeters: 20_000, startBearingDegrees: 270),
    ]
}
