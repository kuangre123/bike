import Foundation

/// 路线上一段的路面情况，来自 BRouter `messages` 里的 `WayTags`。
///
/// 一段可能跨多个坐标点。`startDistanceMeters` 是这段起点距路线起点的累计距离，
/// 用来告诉用户「距起点 2.1 公里处有 300 米非铺装」。
public struct RouteSegment: Equatable, Sendable {
    public let startDistanceMeters: Double
    public let lengthMeters: Double
    /// 原始 OSM 标签，如 `["highway": "tertiary", "surface": "asphalt"]`。
    public let tags: [String: String]

    public init(startDistanceMeters: Double, lengthMeters: Double, tags: [String: String]) {
        self.startDistanceMeters = startDistanceMeters
        self.lengthMeters = lengthMeters
        self.tags = tags
    }

    public var surface: String? { tags["surface"] }
    public var highway: String? { tags["highway"] }

    /// 是不是铺装路面。
    ///
    /// **判不出来就是 nil，不猜。** OSM 的 `surface` 标签覆盖率并不完整，
    /// 缺标签不等于是土路，也不等于是柏油路——那种情况不该给用户任何结论。
    public var isPaved: Bool? {
        guard let surface else { return nil }
        if RouteTerrain.pavedSurfaces.contains(surface) { return true }
        if RouteTerrain.unpavedSurfaces.contains(surface) { return false }
        return nil
    }

    /// 这段路有没有自行车道（`cycleway`、`cycleway:left/right/both`）。
    public var hasCycleway: Bool {
        if highway == "cycleway" { return true }
        return tags.keys.contains { $0 == "cycleway" || $0.hasPrefix("cycleway:") }
    }
}

/// 路面 / 道路等级的分类标准。集中放一处，避免判断散落在各处。
public enum RouteTerrain {
    /// OSM `surface` 里算铺装的取值。
    public static let pavedSurfaces: Set<String> = [
        "asphalt", "paved", "concrete", "concrete:lanes", "concrete:plates",
        "paving_stones", "sett", "metal", "wood",
    ]

    /// 算非铺装的取值。`cobblestone` 虽然是铺的，但对公路车而言等同烂路，归这类。
    public static let unpavedSurfaces: Set<String> = [
        "unpaved", "gravel", "fine_gravel", "compacted", "dirt", "earth", "ground",
        "grass", "sand", "mud", "pebblestone", "rock", "woodchips", "cobblestone",
    ]

    /// 车多、对骑行不友好的道路等级。没有自行车道时才提示。
    public static let busyHighways: Set<String> = [
        "motorway", "motorway_link", "trunk", "trunk_link", "primary", "primary_link",
    ]

    /// 行人道路：骑不了，只能推车过（台阶更是抬车）。
    ///
    /// 不含 `path` —— 那是山地车 / Gravel 的正常路面，一并警告会把这两个档变得没法用。
    public static let footOnlyHighways: Set<String> = ["footway", "steps", "pedestrian"]

    /// 把 BRouter 的 `"highway=tertiary surface=asphalt"` 解析成字典。
    /// 值里含 `=` 时只按第一个 `=` 切（如 `cycleway:right=lane`）。
    public static func parseTags(_ raw: String) -> [String: String] {
        var tags: [String: String] = [:]
        for pair in raw.split(separator: " ") {
            guard let sep = pair.firstIndex(of: "=") else { continue }
            let key = String(pair[pair.startIndex..<sep])
            let value = String(pair[pair.index(after: sep)...])
            guard !key.isEmpty, !value.isEmpty else { continue }
            tags[key] = value
        }
        return tags
    }
}
