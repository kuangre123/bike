import Foundation
import WatchConnectivity
import CyclingDomain

/// 手机 ↔ 手表的 WatchConnectivity 通道：
/// 发「今日概览」给手表，收手表推来的实时心率。
///
/// 手表心率虽然最终也会回写进 Apple 健康，但要等系统后台同步，通常慢几十秒到
/// 几分钟；码表要显示当前心率只能靠这条实时通道。
@MainActor
final class PhoneWatchSync: NSObject, ObservableObject, WCSessionDelegate {
    static let shared = PhoneWatchSync()

    /// 手表推来的最新心率。`measuredAt` 是测量时间而非收到时间，
    /// 判新鲜度、和 HealthKit 样本比谁更新都要用它。
    @Published private(set) var watchHeartRate: WatchHeartRate?

    override init() {
        super.init()
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    func send(_ summary: WatchDaySummary) {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        guard session.activationState == .activated else { return }
        guard let data = try? JSONEncoder().encode(summary) else { return }
        try? session.updateApplicationContext(["today": data])
    }

    private func ingest(_ reading: WatchHeartRate) {
        watchHeartRate = WatchHeartRate.fresher(watchHeartRate, reading)
    }

    /// 在回调线程内解码成 Sendable 的读数，再 hop 到主 actor（`[String: Any]` 不是 Sendable）。
    private nonisolated static func decodeHeartRate(_ payload: [String: Any]) -> WatchHeartRate? {
        guard let data = payload["heartRate"] as? Data else { return nil }
        return try? JSONDecoder().decode(WatchHeartRate.self, from: data)
    }

    nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        let reading = Self.decodeHeartRate(session.receivedApplicationContext)
        Task { @MainActor in if let reading { self.ingest(reading) } }
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        let reading = Self.decodeHeartRate(message)
        Task { @MainActor in if let reading { self.ingest(reading) } }
    }

    nonisolated func session(
        _ session: WCSession,
        didReceiveApplicationContext applicationContext: [String: Any]
    ) {
        let reading = Self.decodeHeartRate(applicationContext)
        Task { @MainActor in if let reading { self.ingest(reading) } }
    }

    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}

    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        WCSession.default.activate()
    }
}
