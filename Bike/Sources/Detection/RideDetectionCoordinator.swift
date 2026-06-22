import Foundation
import CoreMotion
import CoreLocation
import SwiftData
import CyclingDomain
import Observation

/// 编排检测：权限、唤醒、实时追踪、回溯对账（动作 + 心率），并落库 + 乐观添加通知。
@MainActor
@Observable
final class RideDetectionCoordinator {
    private let container: ModelContainer
    private let permissions: PermissionsManager
    private let notifications: NotificationService
    private let motionHistory = MotionHistoryService()
    private let liveTracker = LiveRideTracker()
    private let wake = LocationWakeService()
    private let health = HealthService()
    private let activityManager = CMMotionActivityManager()

    private var pendingTracked: [TrackedRide] = []
    private var liveStopTask: Task<Void, Never>?
    private var started = false
    private var monitoring = false

    private(set) var lastReconcileDate: Date?
    private(set) var savedRideCount: Int = 0

    init(container: ModelContainer, permissions: PermissionsManager) {
        self.container = container
        self.permissions = permissions
        self.notifications = NotificationService(container: container)
    }

    private var isAuthorized: Bool {
        let loc = permissions.locationStatus
        let locOK = (loc == .authorizedAlways || loc == .authorizedWhenInUse)
        return locOK || permissions.motionStatus == .authorized
    }

    /// 冷启动（幂等）：**不弹任何权限**。已授权用户静默开始；未授权静待用户从首页开启。
    func start() {
        guard !started else { return }
        started = true
        guard isAuthorized else { return }
        beginMonitoring()
        Task { await runReconciliation() }
    }

    /// 用户在首页点「开启自动检测」时调用：申请权限并开始检测。
    func enableDetection() {
        notifications.requestAuthorization()
        permissions.requestAll()
        Task {
            _ = await health.requestReadAuthorization()
            beginMonitoring()
            await runReconciliation()
        }
    }

    private func beginMonitoring() {
        guard !monitoring else { return }
        monitoring = true
        wake.onSignificantChange = { [weak self] in
            Task { await self?.runReconciliation() }
        }
        wake.start()
        startActivityMonitoring()
    }

    private func startActivityMonitoring() {
        guard CMMotionActivityManager.isActivityAvailable() else { return }
        activityManager.startActivityUpdates(to: .main) { [weak self] activity in
            guard let activity else { return }
            let type = MotionHistoryService.activityType(of: activity)
            let confident = activity.confidence != .low
            Task { @MainActor in
                self?.handleLiveActivity(type: type, confident: confident)
            }
        }
    }

    private func handleLiveActivity(type: ActivityType?, confident: Bool) {
        if let type, confident {
            liveStopTask?.cancel()
            liveStopTask = nil
            if !liveTracker.isRunning {
                liveTracker.start(activityType: type) { [weak self] ride in
                    guard let self else { return }
                    self.pendingTracked.append(ride)
                    Task { await self.runReconciliation() }
                }
            }
        } else if liveTracker.isRunning, liveStopTask == nil {
            liveStopTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(90))
                guard !Task.isCancelled else { return }
                guard let self else { return }
                await MainActor.run {
                    self.liveStopTask = nil
                    if self.liveTracker.isRunning {
                        self.liveTracker.stop()
                    }
                }
            }
        }
    }

    /// 回溯 [now-window, now] 运动历史 + 心率，与已采 tracked 对账，落库去重。
    /// 刚结束（20 分钟内）的新运动 → 推「已记录 · 撤销」通知（乐观添加）。
    func runReconciliation(window: TimeInterval = 7 * 24 * 3600) async {
        let now = Date()
        let from = now.addingTimeInterval(-window)

        // 基线：动作历史时段
        let rawSegments = await motionHistory.activitySegments(from: from, to: now)
        let segments = mergeActivitySegments(
            rawSegments,
            maxGap: RideDetectionPolicy.defaultMotionMergeGap,
            minDuration: RideDetectionPolicy.minimumRideDuration,
            gapForType: RideDetectionPolicy.motionMergeGap(for:),
            minDurationForType: RideDetectionPolicy.minimumDuration(for:)
        )

        // 心率：兜底检测出动作分类不到的运动 + 给已检测运动附均心率
        let hrSamples = await health.heartRateSamples(from: from, to: now)
        let resting = await health.restingHeartRate(asOf: now)
        let hrSegments = detectElevatedHRSegments(from: hrSamples, restingBPM: resting)

        let tracked = pendingTracked
        pendingTracked = []
        let rides = RideReconciler.reconcile(
            motionSegments: segments, trackedRides: tracked, heartRateSegments: hrSegments
        )
        lastReconcileDate = now
        guard !rides.isEmpty else { return }

        let context = ModelContext(container)
        let store = RideStore(context: context)
        let inserted = (try? store.save(rides, autoDetected: true)) ?? []
        savedRideCount += inserted.count

        // 写回 Apple 健康（默认开；含路线）。回填 workout UUID 便于后续去重 / 删除联动。
        let writeBack = UserDefaults.standard.object(forKey: "healthWriteBack") as? Bool ?? true
        if writeBack, await health.requestWriteAuthorization() {
            for model in inserted {
                let route = RideMapping.decodeRoute(model.routeData)
                if let uuid = await health.saveWorkout(
                    activityType: RideMapping.activityType(of: model),
                    start: model.startDate, end: model.endDate,
                    calories: model.calories,
                    distanceMeters: model.distanceMeters,
                    avgSpeedMps: model.avgSpeedMps,
                    route: route
                ) {
                    model.healthKitWorkoutUUID = uuid
                }
            }
            try? context.save()
        }

        for model in inserted where now.timeIntervalSince(model.endDate) < 20 * 60 {
            notifications.notifyWorkoutAdded(
                rideID: model.rideID,
                activityType: RideMapping.activityType(of: model),
                duration: model.duration
            )
        }
    }
}
