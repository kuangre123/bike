import Foundation
import CoreMotion
import SwiftData
import CyclingDomain
import Observation

/// 编排检测：权限、唤醒、实时追踪、回溯对账，并落库去重。
@MainActor
@Observable
final class RideDetectionCoordinator {
    private let container: ModelContainer
    private let permissions: PermissionsManager
    private let motionHistory = MotionHistoryService()
    private let liveTracker = LiveRideTracker()
    private let wake = LocationWakeService()
    private let activityManager = CMMotionActivityManager()
    private let activityQueue = OperationQueue()

    private var pendingTracked: [TrackedRide] = []
    private var started = false

    private(set) var lastReconcileDate: Date?
    private(set) var savedRideCount: Int = 0

    init(container: ModelContainer, permissions: PermissionsManager) {
        self.container = container
        self.permissions = permissions
    }

    /// 启动检测（幂等）：请求权限、监听唤醒与实时活动、首次对账。
    func start() {
        guard !started else { return }
        started = true
        permissions.requestAll()
        wake.onSignificantChange = { [weak self] in
            Task { await self?.runReconciliation() }
        }
        wake.start()
        startActivityMonitoring()
        Task { await runReconciliation() }
    }

    private func startActivityMonitoring() {
        guard CMMotionActivityManager.isActivityAvailable() else { return }
        activityManager.startActivityUpdates(to: activityQueue) { [weak self] activity in
            guard let activity else { return }
            let isCycling = activity.cycling
            let confident = activity.confidence != .low
            Task { @MainActor in
                self?.handleLiveActivity(isCycling: isCycling, confident: confident)
            }
        }
    }

    private func handleLiveActivity(isCycling: Bool, confident: Bool) {
        if isCycling, confident, !liveTracker.isRunning {
            liveTracker.start { [weak self] ride in
                guard let self else { return }
                self.pendingTracked.append(ride)
                Task { await self.runReconciliation() }
            }
        } else if !isCycling, liveTracker.isRunning {
            liveTracker.stop()
        }
    }

    /// 回溯 [now-window, now] 的运动历史，与已采 tracked 对账，落库去重。
    func runReconciliation(window: TimeInterval = 7 * 24 * 3600) async {
        let now = Date()
        let from = now.addingTimeInterval(-window)
        let rawSegments = await motionHistory.cyclingSegments(from: from, to: now)
        let segments = mergeCyclingSegments(rawSegments, maxGap: 60, minDuration: 90)
        let tracked = pendingTracked
        pendingTracked = []
        let rides = RideReconciler.reconcile(motionSegments: segments, trackedRides: tracked)
        lastReconcileDate = now
        guard !rides.isEmpty else { return }
        let store = RideStore(context: ModelContext(container))
        let inserted = (try? store.save(rides)) ?? 0
        savedRideCount += inserted
    }
}
