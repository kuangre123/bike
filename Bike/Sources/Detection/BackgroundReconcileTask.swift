import Foundation
import BackgroundTasks

/// 后台对账任务：周期性回溯运动历史，补上实时检测漏掉的骑行。
enum BackgroundReconcileTask {
    static let identifier = "com.bochen.bike.reconcile"

    /// 把非 Sendable 的 BGTask 桥接进并发上下文（访问点都在合理线程，安全）。
    private final class Box: @unchecked Sendable {
        let task: BGTask
        init(_ task: BGTask) { self.task = task }
    }

    /// 在 App 启动时注册（必须早于启动完成）。
    ///
    /// 关键：启动回调闭包必须标 `@Sendable`（非隔离）。否则因 `register` 处于 `@MainActor`
    /// 上下文，闭包会被推断为 `@MainActor` 隔离，而 BGTaskScheduler 在**后台队列**上调用它，
    /// Swift 6 运行时进入闭包即做主线程隔离检查 → `_dispatch_assert_queue_fail` 崩溃。
    /// 需要主线程的工作只在内部 `Task { @MainActor in }` 里做。
    @MainActor
    static func register(coordinator: RideDetectionCoordinator) {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: identifier, using: nil) { @Sendable task in
            schedule() // 立刻排下一次
            let box = Box(task)
            let work = Task { @MainActor in
                await coordinator.runReconciliation()
                box.task.setTaskCompleted(success: true)
            }
            box.task.expirationHandler = { work.cancel() }
        }
    }

    /// 安排下一次后台对账（最早 15 分钟后；系统决定实际时机）。
    static func schedule() {
        let request = BGAppRefreshTaskRequest(identifier: identifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60)
        try? BGTaskScheduler.shared.submit(request)
    }
}
