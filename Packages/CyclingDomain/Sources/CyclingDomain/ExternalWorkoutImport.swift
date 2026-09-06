import Foundation

/// 从 Apple 健康导入第三方运动记录的纯决策：筛哪些、怎么映射、删除墓碑怎么维护。
///
/// Garmin Connect / 华为运动健康 / Zepp / Wahoo / Keep / Strava 都会把运动写进 Apple 健康，
/// 所以不必逐家对接 SDK——读健康即可。代价是同一次骑行可能被记两遍（对方一条、
/// 本 app 的被动检测一条），落库时的时间重叠去重在 `RideStore` 里做。
public enum ExternalWorkoutImport {
    /// 删除墓碑保留条数。用户删掉的外部运动不能在下次导入时自己长回来，
    /// 但也不必无限记着——超过上限丢最旧的。
    public static let dismissedLimit = 500

    /// 筛出该导入的外部运动，按开始时间升序。
    ///
    /// - Parameters:
    ///   - enabledSourceIDs: 用户在设置里勾选的来源；默认不勾，不会偷偷往时间线里塞东西。
    ///   - alreadyImported: 已经导入过的 HealthKit workout UUID。
    ///   - dismissed: 用户导入后又删掉的，不再重来。
    public static func importable(
        _ workouts: [ExternalWorkout],
        enabledSourceIDs: Set<String>,
        alreadyImported: Set<UUID>,
        dismissed: Set<UUID>
    ) -> [ExternalWorkout] {
        workouts
            .filter { enabledSourceIDs.contains($0.source.id) }
            .filter { !alreadyImported.contains($0.id) && !dismissed.contains($0.id) }
            .filter { $0.duration >= RideDetectionPolicy.minimumDuration(for: $0.activityType) }
            .sorted { $0.start < $1.start }
    }

    /// 外部运动 → 领域 `Ride`。
    ///
    /// 只搬对方实测的值：没记距离就没有距离，也就没有均速——不拿轨迹或时长去凑一个数。
    /// `activeDuration` 留 nil，因为外部记录只给起止时间，不知道中途停了多久。
    /// `confidence` 给 2（高）：这是真设备记的，不是本 app 从动作历史猜的。
    public static func ride(from workout: ExternalWorkout) -> Ride {
        let duration = workout.duration
        let avgSpeed: Double? = {
            guard let distance = workout.distanceMeters, duration > 0 else { return nil }
            return distance / duration
        }()
        return Ride(
            activityType: workout.activityType,
            start: workout.start,
            end: workout.end,
            source: .externalImport,
            distanceMeters: workout.distanceMeters,
            avgSpeedMps: avgSpeed,
            calories: workout.calories,
            confidence: 2,
            avgHeartRate: workout.avgHeartRate,
            activeDuration: nil,
            route: workout.route.isEmpty ? nil : workout.route
        )
    }

    /// 往删除墓碑里追加一条，去重并裁到上限（丢最旧的）。
    public static func appendingDismissed(
        _ existing: [UUID],
        _ workoutID: UUID,
        limit: Int = dismissedLimit
    ) -> [UUID] {
        guard !existing.contains(workoutID) else { return existing }
        let appended = existing + [workoutID]
        guard appended.count > limit else { return appended }
        return Array(appended.suffix(limit))
    }
}
