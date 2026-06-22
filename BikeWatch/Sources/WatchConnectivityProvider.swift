import Foundation
import WatchConnectivity
import WidgetKit
import CyclingDomain
import Observation

/// 手表侧接收手机同步的今日概览；同时写入 app group 供表盘 complication 读取。
@MainActor
@Observable
final class WatchConnectivityProvider: NSObject, WCSessionDelegate {
    private(set) var today: WatchDaySummary?

    override init() {
        super.init()
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
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
