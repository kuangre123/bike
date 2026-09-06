import Foundation

/// 往 Apple 健康写运动的第三方 app / 设备，例如 Garmin Connect、华为运动健康、Zepp、Keep。
///
/// `id` 是 HealthKit 里那个来源的 bundle identifier —— 同一家 app 换名字后 id 不变，
/// 所以用户的勾选不会因为对方改名而失效。
public struct ExternalWorkoutSource: Sendable, Equatable, Hashable, Identifiable, Codable {
    public let id: String
    public let name: String

    public init(id: String, name: String) {
        self.id = id
        self.name = name
    }
}

/// Apple 健康里一条**别人写的**运动记录。
///
/// 这些字段是对方设备实测后写进健康的值，本 app 只搬运不加工：
/// 设备没记距离就是 nil，不用轨迹去反推。
public struct ExternalWorkout: Sendable, Equatable, Identifiable {
    /// HealthKit workout 的 UUID，用来判断这条是不是已经导入过。
    public let id: UUID
    public let source: ExternalWorkoutSource
    public let activityType: ActivityType
    public let start: Date
    public let end: Date
    public let distanceMeters: Double?
    public let calories: Double?
    public let avgHeartRate: Double?
    /// 对方写入的 GPS 路线；没记路线时为空。
    public let route: [GPSSample]

    public init(
        id: UUID,
        source: ExternalWorkoutSource,
        activityType: ActivityType,
        start: Date,
        end: Date,
        distanceMeters: Double? = nil,
        calories: Double? = nil,
        avgHeartRate: Double? = nil,
        route: [GPSSample] = []
    ) {
        self.id = id
        self.source = source
        self.activityType = activityType
        self.start = start
        self.end = end
        self.distanceMeters = distanceMeters
        self.calories = calories
        self.avgHeartRate = avgHeartRate
        self.route = route
    }

    public var duration: TimeInterval { end.timeIntervalSince(start) }

    /// 补上路线和均心率的副本。
    ///
    /// 读路线 / 心率每条都要单独查一次 HealthKit，所以列出候选时先不读，
    /// 等筛掉「已导入 / 太短 / 已忽略」的之后，只给真要导入的这几条补。
    public func withDetails(avgHeartRate: Double?, route: [GPSSample]) -> ExternalWorkout {
        ExternalWorkout(
            id: id, source: source, activityType: activityType, start: start, end: end,
            distanceMeters: distanceMeters, calories: calories,
            avgHeartRate: avgHeartRate, route: route
        )
    }
}
