import Foundation
import HealthKit
import CyclingDomain
import Observation

/// 手表运动会话：HKWorkoutSession + 实时 builder，采集心率/能量并写入 HealthKit。
/// 采到的心率进 HealthKit，手机端的心率检测会读取，形成闭环。
@MainActor
@Observable
final class WatchWorkoutManager: NSObject {
    private let store = HKHealthStore()
    private var session: HKWorkoutSession?
    private var builder: HKLiveWorkoutBuilder?

    private(set) var isRunning = false
    private(set) var heartRate: Double = 0
    private(set) var activeCalories: Double = 0
    private(set) var startDate: Date?

    func requestAuthorization() async {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        let share: Set<HKSampleType> = [HKObjectType.workoutType()]
        var read: Set<HKObjectType> = [HKObjectType.workoutType()]
        if let hr = HKObjectType.quantityType(forIdentifier: .heartRate) { read.insert(hr) }
        if let e = HKObjectType.quantityType(forIdentifier: .activeEnergyBurned) { read.insert(e) }
        try? await store.requestAuthorization(toShare: share, read: read)
    }

    func start(activityType: ActivityType) {
        guard !isRunning, HKHealthStore.isHealthDataAvailable() else { return }
        let config = HKWorkoutConfiguration()
        config.activityType = Self.workoutType(activityType)
        config.locationType = .outdoor
        do {
            let session = try HKWorkoutSession(healthStore: store, configuration: config)
            let builder = session.associatedWorkoutBuilder()
            builder.dataSource = HKLiveWorkoutDataSource(healthStore: store, workoutConfiguration: config)
            session.delegate = self
            builder.delegate = self
            self.session = session
            self.builder = builder
            let begin = Date()
            startDate = begin
            isRunning = true
            session.startActivity(with: begin)
            builder.beginCollection(withStart: begin) { _, _ in }
        } catch {
            isRunning = false
        }
    }

    func end() {
        session?.end()
        builder?.endCollection(withEnd: Date()) { [weak self] _, _ in
            self?.builder?.finishWorkout { _, _ in }
            Task { @MainActor in self?.reset() }
        }
    }

    private func reset() {
        isRunning = false
        session = nil
        builder = nil
        startDate = nil
        heartRate = 0
        activeCalories = 0
    }

    fileprivate func apply(heartRate: Double?, calories: Double?) {
        if let heartRate { self.heartRate = heartRate }
        if let calories { self.activeCalories = calories }
    }

    static func workoutType(_ t: ActivityType) -> HKWorkoutActivityType {
        switch t {
        case .walking: return .walking
        case .running: return .running
        case .cycling: return .cycling
        case .other:   return .other
        }
    }
}

extension WatchWorkoutManager: HKWorkoutSessionDelegate {
    nonisolated func workoutSession(
        _ session: HKWorkoutSession,
        didChangeTo toState: HKWorkoutSessionState,
        from fromState: HKWorkoutSessionState,
        date: Date
    ) {}

    nonisolated func workoutSession(_ session: HKWorkoutSession, didFailWithError error: Error) {}
}

extension WatchWorkoutManager: HKLiveWorkoutBuilderDelegate {
    nonisolated func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {}

    nonisolated func workoutBuilder(
        _ workoutBuilder: HKLiveWorkoutBuilder,
        didCollectDataOf collectedTypes: Set<HKSampleType>
    ) {
        // 在回调线程内把非 Sendable 的统计取成 Sendable 的 Double，再 hop 到主 actor。
        let hrUnit = HKUnit.count().unitDivided(by: .minute())
        var hr: Double?
        var cal: Double?
        if let t = HKQuantityType.quantityType(forIdentifier: .heartRate), collectedTypes.contains(t) {
            hr = workoutBuilder.statistics(for: t)?.mostRecentQuantity()?.doubleValue(for: hrUnit)
        }
        if let t = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned), collectedTypes.contains(t) {
            cal = workoutBuilder.statistics(for: t)?.sumQuantity()?.doubleValue(for: .kilocalorie())
        }
        Task { @MainActor [hr, cal] in
            self.apply(heartRate: hr, calories: cal)
        }
    }
}
