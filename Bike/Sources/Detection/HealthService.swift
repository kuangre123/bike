import Foundation
import HealthKit
import CoreLocation
import CyclingDomain

/// 读写 HealthKit：读心率（兜底检测）+ 写运动 workout（含 GPS 路线）。
/// 心率需 Apple Watch 记录；无表 / 无数据时读返回空，检测自动退回纯动作。
@MainActor
final class HealthService {
    private let store = HKHealthStore()

    var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    /// ActivityType → HealthKit workout 类型。
    nonisolated static func workoutActivityType(for type: ActivityType) -> HKWorkoutActivityType {
        switch type {
        case .walking: return .walking
        case .running: return .running
        case .cycling: return .cycling
        case .other:   return .other
        }
    }

    func requestReadAuthorization() async -> Bool {
        guard isAvailable else { return false }
        var read: Set<HKObjectType> = []
        if let hr = HKObjectType.quantityType(forIdentifier: .heartRate) { read.insert(hr) }
        if let resting = HKObjectType.quantityType(forIdentifier: .restingHeartRate) { read.insert(resting) }
        guard !read.isEmpty else { return true }

        return await withCheckedContinuation { (cont: CheckedContinuation<Bool, Never>) in
            store.requestAuthorization(toShare: [], read: read) { success, _ in
                cont.resume(returning: success)
            }
        }
    }

    func requestWriteAuthorization() async -> Bool {
        guard isAvailable else { return false }
        let share = writeTypes()
        guard !share.isEmpty else { return false }
        let read: Set<HKObjectType> = [HKObjectType.workoutType()]

        return await withCheckedContinuation { (cont: CheckedContinuation<Bool, Never>) in
            store.requestAuthorization(toShare: share, read: read) { [weak self] _, _ in
                Task { @MainActor in
                    cont.resume(returning: self?.hasWorkoutWriteAuthorization ?? false)
                }
            }
        }
    }

    private var hasWorkoutWriteAuthorization: Bool {
        store.authorizationStatus(for: HKObjectType.workoutType()) == .sharingAuthorized
    }

    private func canWrite(_ type: HKSampleType) -> Bool {
        store.authorizationStatus(for: type) == .sharingAuthorized
    }

    private func writeTypes() -> Set<HKSampleType> {
        var share: Set<HKSampleType> = [HKObjectType.workoutType(), HKSeriesType.workoutRoute()]
        if let e = HKObjectType.quantityType(forIdentifier: .activeEnergyBurned) { share.insert(e) }
        if let b = HKObjectType.quantityType(forIdentifier: .basalEnergyBurned) { share.insert(b) }
        if let dC = HKObjectType.quantityType(forIdentifier: .distanceCycling) { share.insert(dC) }
        if let dWR = HKObjectType.quantityType(forIdentifier: .distanceWalkingRunning) { share.insert(dWR) }
        if #available(iOS 17.0, *),
           let sC = HKObjectType.quantityType(forIdentifier: .cyclingSpeed) {
            share.insert(sC)
        }
        return share
    }

    // MARK: - 读心率（兜底检测）

    /// [from, to] 的心率样本（bpm，按时间升序）。
    func heartRateSamples(from: Date, to: Date) async -> [HeartRateSample] {
        guard isAvailable, let hrType = HKQuantityType.quantityType(forIdentifier: .heartRate) else { return [] }
        let predicate = HKQuery.predicateForSamples(withStart: from, end: to, options: .strictStartDate)
        let sort = [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)]
        return await withCheckedContinuation { (cont: CheckedContinuation<[HeartRateSample], Never>) in
            let query = HKSampleQuery(
                sampleType: hrType, predicate: predicate,
                limit: HKObjectQueryNoLimit, sortDescriptors: sort
            ) { _, samples, _ in
                let unit = HKUnit.count().unitDivided(by: .minute())
                let mapped: [HeartRateSample] = (samples as? [HKQuantitySample] ?? []).map {
                    HeartRateSample(timestamp: $0.startDate, bpm: $0.quantity.doubleValue(for: unit))
                }
                cont.resume(returning: mapped)
            }
            store.execute(query)
        }
    }

    /// 最近 14 天的静息心率；无数据回退 60。
    func restingHeartRate(asOf date: Date) async -> Double {
        guard isAvailable, let type = HKQuantityType.quantityType(forIdentifier: .restingHeartRate) else { return 60 }
        let predicate = HKQuery.predicateForSamples(withStart: date.addingTimeInterval(-14 * 24 * 3600), end: date, options: [])
        let sort = [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)]
        return await withCheckedContinuation { (cont: CheckedContinuation<Double, Never>) in
            let query = HKSampleQuery(
                sampleType: type, predicate: predicate,
                limit: 1, sortDescriptors: sort
            ) { _, samples, _ in
                let unit = HKUnit.count().unitDivided(by: .minute())
                let bpm = (samples as? [HKQuantitySample])?.first?.quantity.doubleValue(for: unit) ?? 60
                cont.resume(returning: bpm)
            }
            store.execute(query)
        }
    }

    // MARK: - 读第三方运动（Garmin / 华为 / Zepp / Keep …）

    /// 读运动记录需要的授权。和写授权分开请求：用户可能只想导入、不想让本 app 写回。
    func requestWorkoutReadAuthorization() async -> Bool {
        guard isAvailable else { return false }
        var read: Set<HKObjectType> = [HKObjectType.workoutType(), HKSeriesType.workoutRoute()]
        if let hr = HKObjectType.quantityType(forIdentifier: .heartRate) { read.insert(hr) }
        return await withCheckedContinuation { (cont: CheckedContinuation<Bool, Never>) in
            store.requestAuthorization(toShare: [], read: read) { success, _ in
                cont.resume(returning: success)
            }
        }
    }

    /// 最近 `days` 天里，除本 app 外往 Apple 健康写过运动的来源，按记录数降序。
    ///
    /// HealthKit 读权限是不可见的：没授权时查询返回空，看起来就是「没有其他设备」。
    /// 所以调用方要先 `requestWorkoutReadAuthorization()`。
    func externalWorkoutSources(days: Int = 365) async -> [(source: ExternalWorkoutSource, count: Int, latest: Date)] {
        let workouts = await rawWorkouts(days: days, sourceIDs: nil)
        var buckets: [String: (name: String, count: Int, latest: Date)] = [:]
        for workout in workouts {
            let source = workout.sourceRevision.source
            guard source.bundleIdentifier != Self.ownBundleIdentifier else { continue }
            let existing = buckets[source.bundleIdentifier]
            buckets[source.bundleIdentifier] = (
                name: source.name,
                count: (existing?.count ?? 0) + 1,
                latest: max(existing?.latest ?? .distantPast, workout.endDate)
            )
        }
        return buckets
            .map { (ExternalWorkoutSource(id: $0.key, name: $0.value.name), $0.value.count, $0.value.latest) }
            .sorted { $0.1 > $1.1 }
    }

    /// 第一遍：指定来源在最近 `days` 天里的运动**概要**（无路线 / 无心率）。
    ///
    /// 故意不在这里读路线和心率——那是每条一次查询的开销，而绝大多数记录会在
    /// `ExternalWorkoutImport.importable` 那步被「已导入 / 太短 / 已忽略」筛掉。
    /// 筛完再对剩下的几条调 `enrich(_:)`。
    func externalWorkoutSummaries(sourceIDs: Set<String>, days: Int = 365) async -> [ExternalWorkout] {
        guard !sourceIDs.isEmpty else { return [] }
        return await rawWorkouts(days: days, sourceIDs: sourceIDs).compactMap(Self.summary(of:))
    }

    /// 第二遍：给筛选后真要导入的记录补上 GPS 路线和均心率。
    func enrich(_ workouts: [ExternalWorkout]) async -> [ExternalWorkout] {
        guard isAvailable, !workouts.isEmpty else { return workouts }
        let byID = await rawWorkouts(uuids: Set(workouts.map(\.id)))
            .reduce(into: [UUID: HKWorkout]()) { $0[$1.uuid] = $1 }
        var result: [ExternalWorkout] = []
        for workout in workouts {
            guard let hk = byID[workout.id] else { result.append(workout); continue }
            result.append(
                workout.withDetails(
                    avgHeartRate: await averageHeartRate(from: workout.start, to: workout.end),
                    route: await route(of: hk)
                )
            )
        }
        return result
    }

    private nonisolated static var ownBundleIdentifier: String {
        Bundle.main.bundleIdentifier ?? ""
    }

    /// `HKWorkout` → 领域概要。本 app 自己写的、或识别不了类型的返回 nil。
    private nonisolated static func summary(of workout: HKWorkout) -> ExternalWorkout? {
        let source = workout.sourceRevision.source
        guard source.bundleIdentifier != ownBundleIdentifier,
              let type = activityType(for: workout.workoutActivityType) else { return nil }
        return ExternalWorkout(
            id: workout.uuid,
            source: ExternalWorkoutSource(id: source.bundleIdentifier, name: source.name),
            activityType: type,
            start: workout.startDate,
            end: workout.endDate,
            distanceMeters: distanceMeters(of: workout, activityType: type),
            calories: activeCalories(of: workout),
            avgHeartRate: nil,
            route: []
        )
    }

    private func rawWorkouts(days: Int, sourceIDs: Set<String>?) async -> [HKWorkout] {
        let now = Date()
        // HealthKit 的来源谓词要 `HKSource` 实例，这里只有 bundle id，所以取回后再过滤。
        let all = await rawWorkouts(
            predicate: HKQuery.predicateForSamples(
                withStart: now.addingTimeInterval(TimeInterval(-days * 24 * 3600)), end: now, options: [])
        )
        guard let sourceIDs else { return all }
        return all.filter { sourceIDs.contains($0.sourceRevision.source.bundleIdentifier) }
    }

    private func rawWorkouts(uuids: Set<UUID>) async -> [HKWorkout] {
        guard !uuids.isEmpty else { return [] }
        return await rawWorkouts(predicate: HKQuery.predicateForObjects(with: uuids))
    }

    private func rawWorkouts(predicate: NSPredicate) async -> [HKWorkout] {
        guard isAvailable else { return [] }
        return await withCheckedContinuation { cont in
            let query = HKSampleQuery(
                sampleType: HKObjectType.workoutType(),
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)]
            ) { _, samples, _ in
                cont.resume(returning: samples as? [HKWorkout] ?? [])
            }
            store.execute(query)
        }
    }

    /// HealthKit workout 类型 → 本 app 的运动类型。
    /// 只认这四种：游泳、力量训练之类进不了骑行日志，返回 nil 直接跳过。
    nonisolated static func activityType(for type: HKWorkoutActivityType) -> ActivityType? {
        switch type {
        case .cycling: return .cycling
        case .running: return .running
        case .walking, .hiking: return .walking
        default: return nil
        }
    }

    /// 对方记了多少就是多少；没记距离就是 nil，不拿时长或轨迹去凑。
    private nonisolated static func distanceMeters(of workout: HKWorkout, activityType: ActivityType) -> Double? {
        let id: HKQuantityTypeIdentifier = activityType == .cycling ? .distanceCycling : .distanceWalkingRunning
        guard let type = HKQuantityType.quantityType(forIdentifier: id),
              let stats = workout.statistics(for: type),
              let sum = stats.sumQuantity() else { return nil }
        return sum.doubleValue(for: .meter())
    }

    private nonisolated static func activeCalories(of workout: HKWorkout) -> Double? {
        guard let type = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned),
              let stats = workout.statistics(for: type),
              let sum = stats.sumQuantity() else { return nil }
        return sum.doubleValue(for: .kilocalorie())
    }

    /// 该时段的平均心率；没有心率样本就是 nil，不拿静息心率之类去填。
    private func averageHeartRate(from: Date, to: Date) async -> Double? {
        let samples = await heartRateSamples(from: from, to: to)
        guard !samples.isEmpty else { return nil }
        return samples.map(\.bpm).reduce(0, +) / Double(samples.count)
    }

    /// 读 workout 关联的 GPS 路线；对方没记路线就是空数组。
    private func route(of workout: HKWorkout) async -> [GPSSample] {
        let routes: [HKWorkoutRoute] = await withCheckedContinuation { cont in
            let query = HKSampleQuery(
                sampleType: HKSeriesType.workoutRoute(),
                predicate: HKQuery.predicateForObjects(from: workout),
                limit: HKObjectQueryNoLimit,
                sortDescriptors: nil
            ) { _, samples, _ in
                cont.resume(returning: samples as? [HKWorkoutRoute] ?? [])
            }
            store.execute(query)
        }
        var samples: [GPSSample] = []
        for route in routes {
            samples += await locations(in: route)
        }
        return samples.sorted { $0.timestamp < $1.timestamp }
    }

    /// `HKWorkoutRouteQuery` 是分批回调的：要一直收到 `done == true` 才算读完。
    /// 读的是已完成的 workout，所以 `done` 之后查询自行结束，不需要 `store.stop`。
    private func locations(in route: HKWorkoutRoute) async -> [GPSSample] {
        await withCheckedContinuation { (cont: CheckedContinuation<[GPSSample], Never>) in
            let collector = RouteCollector()
            let query = HKWorkoutRouteQuery(route: route) { _, locations, done, error in
                if let locations {
                    collector.append(locations.map {
                        GPSSample(
                            timestamp: $0.timestamp,
                            latitude: $0.coordinate.latitude,
                            longitude: $0.coordinate.longitude,
                            // 没有有效速度 / 海拔时 CoreLocation 给负值，按缺失处理，不猜。
                            speedMps: $0.speed,
                            altitude: $0.verticalAccuracy >= 0 ? $0.altitude : nil
                        )
                    })
                }
                guard done || error != nil, let samples = collector.finish() else { return }
                cont.resume(returning: samples)
            }
            store.execute(query)
        }
    }

    // MARK: - 写运动

    /// HealthKit 里已有的「本 app + 同类型 + 近似同时间」运动；用于幂等写入和重复清理。
    private func matchingWorkouts(activityType: ActivityType, start: Date, end: Date) async -> [HKWorkout] {
        let timePred = HKQuery.predicateForSamples(
            withStart: start.addingTimeInterval(-120), end: end.addingTimeInterval(120), options: [])
        let sourcePred = HKQuery.predicateForObjects(from: HKSource.default())
        let typePred = HKQuery.predicateForWorkouts(with: Self.workoutActivityType(for: activityType))
        let pred = NSCompoundPredicate(andPredicateWithSubpredicates: [timePred, sourcePred, typePred])
        let workouts: [HKWorkout] = await withCheckedContinuation { (cont: CheckedContinuation<[HKWorkout], Never>) in
            let query = HKSampleQuery(
                sampleType: HKObjectType.workoutType(),
                predicate: pred,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)]
            ) { _, samples, _ in
                cont.resume(returning: samples as? [HKWorkout] ?? [])
            }
            store.execute(query)
        }
        return workouts.filter {
            abs($0.startDate.timeIntervalSince(start)) <= 120
                && abs($0.endDate.timeIntervalSince(end)) <= 120
        }
    }

    private func deleteDuplicateWorkouts(_ workouts: [HKWorkout]) async {
        guard !workouts.isEmpty else { return }
        for workout in workouts {
            _ = await withCheckedContinuation { cont in
                store.delete(workout) { success, _ in
                    cont.resume(returning: success)
                }
            }
        }
    }

    func cleanupDuplicateWorkouts(days: Int = 30) async -> Int {
        guard isAvailable, hasWorkoutWriteAuthorization else { return 0 }
        let now = Date()
        let predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            HKQuery.predicateForSamples(
                withStart: now.addingTimeInterval(TimeInterval(-days * 24 * 3600)),
                end: now,
                options: []
            ),
            HKQuery.predicateForObjects(from: HKSource.default())
        ])
        let workouts: [HKWorkout] = await withCheckedContinuation { cont in
            let query = HKSampleQuery(
                sampleType: HKObjectType.workoutType(),
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)]
            ) { _, samples, _ in
                cont.resume(returning: samples as? [HKWorkout] ?? [])
            }
            store.execute(query)
        }

        let grouped = Dictionary(grouping: workouts, by: duplicateGroupKey(for:))
        let duplicates = grouped.values.flatMap { group in
            Array(group.dropFirst())
        }
        await deleteDuplicateWorkouts(duplicates)
        return duplicates.count
    }

    private func duplicateGroupKey(for workout: HKWorkout) -> String {
        let startBucket = Int(workout.startDate.timeIntervalSince1970 / 120)
        let endBucket = Int(workout.endDate.timeIntervalSince1970 / 120)
        return "\(workout.workoutActivityType.rawValue)-\(startBucket)-\(endBucket)"
    }

    /// 把一条运动写成 `HKWorkout`（含能量 / 距离 / GPS 路线）。返回 workout UUID；失败 nil。
    /// 幂等：HealthKit 里已有同 app/类型/时间段的运动则直接返回，不重复写。
    func saveWorkout(
        activityType: ActivityType, start: Date, end: Date,
        calories: Double?, distanceMeters: Double?, avgSpeedMps: Double? = nil, route: [RoutePointDTO]
    ) async -> UUID? {
        guard isAvailable, hasWorkoutWriteAuthorization else { return nil }
        let existing = await matchingWorkouts(activityType: activityType, start: start, end: end)
        if let workout = existing.first {
            await deleteDuplicateWorkouts(Array(existing.dropFirst()))
            return workout.uuid
        }
        let config = HKWorkoutConfiguration()
        config.activityType = Self.workoutActivityType(for: activityType)
        let builder = HKWorkoutBuilder(healthStore: store, configuration: config, device: .local())
        do {
            try await builder.beginCollection(at: start)

            var samples: [HKSample] = []
            if let kcal = calories,
               let t = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned),
               canWrite(t) {
                samples.append(HKQuantitySample(
                    type: t, quantity: HKQuantity(unit: .kilocalorie(), doubleValue: kcal),
                    start: start, end: end))
            }
            if let basalKcal = restingEnergyKcal(start: start, end: end),
               let t = HKQuantityType.quantityType(forIdentifier: .basalEnergyBurned),
               canWrite(t) {
                samples.append(HKQuantitySample(
                    type: t, quantity: HKQuantity(unit: .kilocalorie(), doubleValue: basalKcal),
                    start: start, end: end))
            }
            if let dist = distanceMeters {
                let id: HKQuantityTypeIdentifier = activityType == .cycling ? .distanceCycling : .distanceWalkingRunning
                if let t = HKQuantityType.quantityType(forIdentifier: id), canWrite(t) {
                    samples.append(HKQuantitySample(
                        type: t, quantity: HKQuantity(unit: .meter(), doubleValue: dist),
                        start: start, end: end))
                }
            }
            if #available(iOS 17.0, *),
               activityType == .cycling,
               let speed = avgSpeedMps,
               let t = HKQuantityType.quantityType(forIdentifier: .cyclingSpeed),
               canWrite(t) {
                samples.append(HKQuantitySample(
                    type: t,
                    quantity: HKQuantity(unit: .meter().unitDivided(by: .second()), doubleValue: speed),
                    start: start,
                    end: end
                ))
            }
            if !samples.isEmpty { try await builder.addSamples(samples) }

            try await builder.endCollection(at: end)
            guard let workout = try await builder.finishWorkout() else { return nil }

            if !route.isEmpty, canWrite(HKSeriesType.workoutRoute()) {
                let routeBuilder = HKWorkoutRouteBuilder(healthStore: store, device: .local())
                let locations = route.map {
                    CLLocation(
                        coordinate: CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude),
                        altitude: 0, horizontalAccuracy: 5, verticalAccuracy: -1,
                        course: -1, speed: max(0, $0.speedMps), timestamp: $0.timestamp)
                }
                do {
                    try await routeBuilder.insertRouteData(locations)
                    try await routeBuilder.finishRoute(with: workout, metadata: nil)
                } catch {
                    // Workout 已经写入成功；路线失败不影响主记录。
                }
            }
            return workout.uuid
        } catch {
            return nil
        }
    }

    func deleteWorkout(uuid: UUID) async -> Bool {
        guard isAvailable, hasWorkoutWriteAuthorization else { return false }
        let predicate = HKQuery.predicateForObject(with: uuid)
        let workouts: [HKWorkout] = await withCheckedContinuation { cont in
            let query = HKSampleQuery(
                sampleType: HKObjectType.workoutType(),
                predicate: predicate,
                limit: 1,
                sortDescriptors: nil
            ) { _, samples, _ in
                cont.resume(returning: samples as? [HKWorkout] ?? [])
            }
            store.execute(query)
        }
        guard let workout = workouts.first else { return false }
        return await withCheckedContinuation { cont in
            store.delete(workout) { success, _ in
                cont.resume(returning: success)
            }
        }
    }

    /// HealthKit 的“总千卡”通常由动态能量 + 静息能量构成；这里用 70kg 的保守默认值估算静息能量。
    private func restingEnergyKcal(start: Date, end: Date) -> Double? {
        let duration = end.timeIntervalSince(start)
        guard duration > 0 else { return nil }
        return 70 * duration / 3600
    }
}

/// `HKWorkoutRouteQuery` 的分批回调可能来自任意线程，用锁攒结果。
/// `finish()` 只会返回一次，防止 `done` 和 error 各回调一次时把 continuation resume 两遍（会崩）。
private final class RouteCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var samples: [GPSSample] = []
    private var finished = false

    func append(_ new: [GPSSample]) {
        lock.lock()
        defer { lock.unlock() }
        samples += new
    }

    func finish() -> [GPSSample]? {
        lock.lock()
        defer { lock.unlock() }
        guard !finished else { return nil }
        finished = true
        return samples
    }
}
