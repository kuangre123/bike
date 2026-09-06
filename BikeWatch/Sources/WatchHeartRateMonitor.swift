import Foundation
import HealthKit
import CyclingDomain
import Observation

/// 手表侧心率读取，不依赖运动会话——首页也能显示。
///
/// 订阅 HealthKit 新写入的心率样本：手表平时几分钟被动测一次，
/// 运动会话中每几秒一次，两种都会走这里。读不到就是读不到，不做任何推算，
/// `latest` 为 nil 时界面显示「--」。
///
/// 授权遵循运动页的做法——不在进入首页时弹窗，只有已经授权过才静默开始；
/// 没授权过时把卡片变成「开启心率」按钮，用户点了再请求。
@MainActor
@Observable
final class WatchHeartRateMonitor {
    private(set) var latest: WatchHeartRate?
    /// 已知请求授权会弹窗（即还没授权过）。此时首页显示「开启心率」按钮。
    private(set) var needsPermission = false

    @ObservationIgnored var onReading: ((WatchHeartRate) -> Void)?

    @ObservationIgnored private let store = HKHealthStore()
    @ObservationIgnored private var query: HKAnchoredObjectQuery?

    var isMonitoring: Bool { query != nil }

    private var heartRateType: HKQuantityType? {
        guard HKHealthStore.isHealthDataAvailable() else { return nil }
        return HKQuantityType.quantityType(forIdentifier: .heartRate)
    }

    /// 已授权则静默开始；未授权不弹窗。
    func startIfAuthorized() async {
        guard query == nil, let type = heartRateType else { return }
        let status = try? await store.statusForAuthorizationRequest(toShare: [], read: [type])
        guard status == .unnecessary else {
            needsPermission = true
            return
        }
        needsPermission = false
        beginQuery(type)
    }

    /// 用户主动点「开启心率」才请求授权。
    /// HealthKit 出于隐私不告诉 app 读权限到底给没给——被拒的话查询就是查不到数据，
    /// 界面照常显示「等待心率」，不假装有值。
    func requestAndStart() async {
        guard query == nil, let type = heartRateType else { return }
        try? await store.requestAuthorization(toShare: [], read: [type])
        needsPermission = false
        beginQuery(type)
    }

    func stop() {
        guard let query else { return }
        store.stop(query)
        self.query = nil
    }

    /// 运动会话里 `HKLiveWorkoutBuilder` 的读数比写进 HealthKit 更早到，直接并进来。
    func ingest(bpm: Double, at date: Date) {
        guard bpm > 0 else { return }
        needsPermission = false
        apply(WatchHeartRate(bpm: bpm, measuredAt: date))
    }

    private func beginQuery(_ type: HKQuantityType) {
        guard query == nil else { return }
        // 只订阅最近这段时间：anchor 为 nil 且不加谓词时，
        // 首次回调会把历史上所有心率样本一次性倒出来。
        let predicate = HKQuery.predicateForSamples(
            withStart: Date().addingTimeInterval(-WatchHeartRate.recentWindow),
            end: nil,
            options: []
        )
        let handler: @Sendable (
            HKAnchoredObjectQuery, [HKSample]?, [HKDeletedObject]?, HKQueryAnchor?, Error?
        ) -> Void = { [weak self] _, samples, _, _, _ in
            guard let reading = Self.newest(in: samples) else { return }
            Task { @MainActor in self?.apply(reading) }
        }
        let query = HKAnchoredObjectQuery(
            type: type,
            predicate: predicate,
            anchor: nil,
            limit: HKObjectQueryNoLimit,
            resultsHandler: handler
        )
        query.updateHandler = handler
        store.execute(query)
        self.query = query
    }

    private func apply(_ reading: WatchHeartRate) {
        // 乱序到达时别让旧样本盖掉新样本。
        if let latest, latest.measuredAt >= reading.measuredAt { return }
        latest = reading
        onReading?(reading)
    }

    private nonisolated static func newest(in samples: [HKSample]?) -> WatchHeartRate? {
        guard let sample = samples?
            .compactMap({ $0 as? HKQuantitySample })
            .max(by: { $0.endDate < $1.endDate }) else { return nil }
        let unit = HKUnit.count().unitDivided(by: .minute())
        return WatchHeartRate(
            bpm: sample.quantity.doubleValue(for: unit),
            measuredAt: sample.endDate
        )
    }
}
