import Foundation
import HealthKit
import CoreLocation
import CyclingDomain
import Observation

/// 手表运动会话：心率/能量（HKWorkoutSession）+ 距离/速度（CoreLocation）。
/// 模拟器不支持 HKWorkoutSession（会崩），用 `#if targetEnvironment(simulator)` 隔离：
/// 模拟器只跑计时 + 定位，真机才开真实 workout session 采心率写 HealthKit。
@MainActor
@Observable
final class WatchWorkoutManager: NSObject {
    /// GPS 点的 Sendable 投影，用于跨 actor 传递。
    private struct LocPoint: Sendable {
        let lat: Double, lon: Double, speed: Double
    }

    private let store = HKHealthStore()
    private let locationManager = CLLocationManager()
    private var lastPoint: LocPoint?

    #if !targetEnvironment(simulator)
    private var session: HKWorkoutSession?
    private var builder: HKLiveWorkoutBuilder?
    #endif

    private(set) var isRunning = false
    private(set) var heartRate: Double = 0
    private(set) var activeCalories: Double = 0
    private(set) var distanceMeters: Double = 0
    private(set) var speedMps: Double = 0
    private(set) var startDate: Date?
    private var activityType: ActivityType = .cycling

    override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
    }

    func requestAuthorization() async {
        locationManager.requestWhenInUseAuthorization()
        guard HKHealthStore.isHealthDataAvailable() else { return }
        let share: Set<HKSampleType> = [HKObjectType.workoutType()]
        var read: Set<HKObjectType> = [HKObjectType.workoutType()]
        if let hr = HKObjectType.quantityType(forIdentifier: .heartRate) { read.insert(hr) }
        if let e = HKObjectType.quantityType(forIdentifier: .activeEnergyBurned) { read.insert(e) }
        try? await store.requestAuthorization(toShare: share, read: read)
    }

    func start(activityType: ActivityType) {
        guard !isRunning else { return }
        self.activityType = activityType
        distanceMeters = 0; speedMps = 0; heartRate = 0; activeCalories = 0
        lastPoint = nil
        startDate = Date()
        isRunning = true
        locationManager.startUpdatingLocation()

        #if !targetEnvironment(simulator)
        guard HKHealthStore.isHealthDataAvailable() else { return }
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
            let begin = startDate ?? Date()
            session.startActivity(with: begin)
            builder.beginCollection(withStart: begin) { _, _ in }
        } catch {
            // 失败则退回计时 + 定位模式
        }
        #endif
    }

    func end() {
        isRunning = false
        locationManager.stopUpdatingLocation()
        #if !targetEnvironment(simulator)
        session?.end()
        builder?.endCollection(withEnd: Date()) { [weak self] _, _ in
            self?.builder?.finishWorkout { _, _ in }
            Task { @MainActor in self?.clearSession() }
        }
        #endif
        startDate = nil
    }

    #if !targetEnvironment(simulator)
    private func clearSession() {
        session = nil
        builder = nil
    }
    #endif

    private func apply(heartRate: Double?, calories: Double?) {
        if let heartRate { self.heartRate = heartRate }
        if let calories { self.activeCalories = calories }
    }

    private func ingest(_ points: [LocPoint]) {
        for p in points {
            if let last = lastPoint {
                distanceMeters += haversineMeters(lat1: last.lat, lon1: last.lon, lat2: p.lat, lon2: p.lon)
            }
            lastPoint = p
            speedMps = p.speed
        }
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

extension WatchWorkoutManager: CLLocationManagerDelegate {
    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let points = locations
            .filter { $0.horizontalAccuracy >= 0 && $0.horizontalAccuracy <= 50 }
            .map { LocPoint(lat: $0.coordinate.latitude, lon: $0.coordinate.longitude, speed: max(0, $0.speed)) }
        guard !points.isEmpty else { return }
        Task { @MainActor in self.ingest(points) }
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
