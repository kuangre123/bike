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
        if hasWorkoutWriteAuthorization {
            return true
        }

        return await withCheckedContinuation { (cont: CheckedContinuation<Bool, Never>) in
            store.requestAuthorization(toShare: share, read: []) { [weak self] _, _ in
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

    // MARK: - 写运动

    /// 把一条运动写成 `HKWorkout`（含能量 / 距离 / GPS 路线）。返回 workout UUID；失败 nil。
    func saveWorkout(
        activityType: ActivityType, start: Date, end: Date,
        calories: Double?, distanceMeters: Double?, avgSpeedMps: Double? = nil, route: [RoutePointDTO]
    ) async -> UUID? {
        guard isAvailable, hasWorkoutWriteAuthorization else { return nil }
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
