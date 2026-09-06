import Foundation
import WatchConnectivity
import WidgetKit
import CyclingDomain
import Observation

/// 手表侧接收手机同步的今日概览；同时写入 app group 供表盘 complication 读取。
/// 反向把手表测到的心率推给手机（手机自己读 HealthKit 要等系统后台回写，慢很多）。
@MainActor
@Observable
final class WatchConnectivityProvider: NSObject, WCSessionDelegate {
    private(set) var today: WatchDaySummary?

    /// 两次推送的最小间隔。HealthKit 偶尔会一次性回调好几批样本，
    /// 没必要为同一时刻的心率反复占用无线电。
    private static let minimumSendInterval: TimeInterval = 2

    @ObservationIgnored private var lastSentAt: Date?

    override init() {
        super.init()
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    /// 把一条心率读数推给手机。
    /// 手机在前台（reachable）时走实时消息；否则退回 applicationContext——
    /// 它会自我覆盖，不像 transferUserInfo 那样排队堆一串过期心率。
    func send(heartRate reading: WatchHeartRate) {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        guard session.activationState == .activated else { return }

        let now = Date()
        if let lastSentAt, now.timeIntervalSince(lastSentAt) < Self.minimumSendInterval { return }
        guard let data = try? JSONEncoder().encode(reading) else { return }
        lastSentAt = now

        if session.isReachable {
            session.sendMessage(["heartRate": data], replyHandler: nil, errorHandler: nil)
        } else {
            try? session.updateApplicationContext(["heartRate": data])
        }
    }

    private func apply(_ summary: WatchDaySummary) {
        today = summary
        let defaults = UserDefaults(suiteName: "group.com.bochen.bike")
        defaults?.set(Int(summary.durationSeconds / 60), forKey: "todayMinutes")
        defaults?.set(summary.count, forKey: "todayCount")
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// 在回调线程内解码成 Sendable 的摘要，再 hop 到主 actor。
    nonisolated static func decode(_ context: [String: Any]) -> WatchDaySummary? {
        guard let data = context["today"] as? Data else { return nil }
        return try? JSONDecoder().decode(WatchDaySummary.self, from: data)
    }

    nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        let summary = Self.decode(session.receivedApplicationContext)
        Task { @MainActor in if let summary { self.apply(summary) } }
    }

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        let summary = Self.decode(applicationContext)
        Task { @MainActor in if let summary { self.apply(summary) } }
    }
}
