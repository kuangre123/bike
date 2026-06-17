import Foundation

/// 持久化用的路线点，JSON 编码进 `RideModel.routeData`。
/// 与领域层 `GPSSample` 字段对应，但归属持久化层（避免领域包承担存储职责）。
struct RoutePointDTO: Codable, Equatable {
    var latitude: Double
    var longitude: Double
    var timestamp: Date
    var speedMps: Double
}
