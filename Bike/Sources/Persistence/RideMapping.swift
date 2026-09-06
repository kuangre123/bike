import Foundation
import CyclingDomain

/// 领域 `Ride` <-> 持久化 `RideModel` 的映射 + 路线编解码。纯函数，可单测。
enum RideMapping {
    /// 由领域 Ride 造一个新的持久化模型（每次生成新 rideID）。
    /// `externalWorkoutUUID` / `externalSourceName` 只在从 Apple 健康导入第三方记录时给值。
    static func makeModel(
        from ride: Ride,
        autoDetected: Bool = false,
        externalWorkoutUUID: UUID? = nil,
        externalSourceName: String? = nil
    ) -> RideModel {
        RideModel(
            rideID: UUID(),
            activityTypeRaw: ride.activityType.rawValue,
            startDate: ride.start,
            endDate: ride.end,
            sourceRaw: ride.source.rawValue,
            distanceMeters: ride.distanceMeters,
            avgSpeedMps: ride.avgSpeedMps,
            calories: ride.calories,
            confidence: ride.confidence,
            routeData: encodeRoute(ride.route),
            avgHeartRate: ride.avgHeartRate,
            activeDurationSeconds: ride.activeDuration,
            externalWorkoutUUID: externalWorkoutUUID,
            externalSourceName: externalSourceName,
            isAutoDetected: autoDetected
        )
    }

    static func source(of model: RideModel) -> RideSource {
        RideSource(rawValue: model.sourceRaw) ?? .motionOnly
    }

    static func activityType(of model: RideModel) -> ActivityType {
        ActivityType(rawValue: model.activityTypeRaw) ?? .cycling
    }

    // MARK: - 路线编解码（[GPSSample] <-> JSON Data <-> [RoutePointDTO]）

    /// 把领域轨迹点编码为 JSON Data；空 / nil 返回 nil。
    static func encodeRoute(_ route: [GPSSample]?) -> Data? {
        guard let route, !route.isEmpty else { return nil }
        let dtos = route.map {
            RoutePointDTO(latitude: $0.latitude, longitude: $0.longitude,
                          timestamp: $0.timestamp, speedMps: $0.speedMps,
                          altitude: $0.altitude)
        }
        return try? JSONEncoder().encode(dtos)
    }

    /// 解码持久化的路线；无 / 失败返回空数组。
    static func decodeRoute(_ data: Data?) -> [RoutePointDTO] {
        guard let data else { return [] }
        return (try? JSONDecoder().decode([RoutePointDTO].self, from: data)) ?? []
    }

    /// 解码为领域 `GPSSample`（用于 GPX 导出等领域函数）。
    static func gpsSamples(_ data: Data?) -> [GPSSample] {
        decodeRoute(data).map {
            GPSSample(timestamp: $0.timestamp, latitude: $0.latitude,
                      longitude: $0.longitude, speedMps: $0.speedMps, altitude: $0.altitude)
        }
    }
}
