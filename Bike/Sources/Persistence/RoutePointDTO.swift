import Foundation

/// 持久化用的路线点，JSON 编码进 `RideModel.routeData`。
/// 与领域层 `GPSSample` 字段对应，但归属持久化层（避免领域包承担存储职责）。
struct RoutePointDTO: Codable, Equatable, Sendable {
    var latitude: Double
    var longitude: Double
    var timestamp: Date
    var speedMps: Double
    /// 海拔（米）。可选：旧记录的 JSON 没有此键，解码得 nil。
    var altitude: Double?

    init(latitude: Double, longitude: Double, timestamp: Date, speedMps: Double, altitude: Double? = nil) {
        self.latitude = latitude
        self.longitude = longitude
        self.timestamp = timestamp
        self.speedMps = speedMps
        self.altitude = altitude
    }
}
