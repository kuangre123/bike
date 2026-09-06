import Foundation
import WatchConnectivity
import CyclingDomain
import os

/// 这条链路失败时全是静默的（sendMessage 的 errorHandler、updateApplicationContext 的 throw
/// 以前都被吞掉），出问题只能靠猜。统一打到 WCSync 分类下，Xcode 控制台过滤 "[WCSync]" 即可。
private let wcLog = Logger(subsystem: "com.bochen.bike", category: "WCSync")

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
        do {
            try session.updateApplicationContext(["today": data])
        } catch {
            wcLog.error("[WCSync] 手机→手表 概览发送失败: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// 手表配对 / 安装状态。收不到心率时，先看这行——`watchAppInstalled=false` 说明手机
    /// 根本不认为手表上装着本 app 的手表端，这时两个方向都传不了，属于安装状态问题而非代码问题。
    nonisolated static func logState(_ label: String, _ session: WCSession) {
        wcLog.notice(
            """
            [WCSync] \(label, privacy: .public) \
            activation=\(session.activationState.rawValue) \
            paired=\(session.isPaired) \
            watchAppInstalled=\(session.isWatchAppInstalled) \
            reachable=\(session.isReachable)
            """
        )
    }

    private func ingest(_ reading: WatchHeartRate) {
        wcLog.notice("[WCSync] 收到手表心率 \(Int(reading.bpm)) bpm，测于 \(reading.measuredAt, privacy: .public)")
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
        if let error {
            wcLog.error("[WCSync] 手机侧 session 激活失败: \(error.localizedDescription, privacy: .public)")
        }
        Self.logState("激活完成", session)
        let reading = Self.decodeHeartRate(session.receivedApplicationContext)
        Task { @MainActor in if let reading { self.ingest(reading) } }
    }

    /// 配对 / 安装状态变化时打一行——手表 app 装上或被删掉都会走到这里。
    nonisolated func sessionWatchStateDidChange(_ session: WCSession) {
        Self.logState("状态变化", session)
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
