import Foundation
import HealthKit
import CyclingDomain

/// 读取 HealthKit 心率 + 静息心率，供心率兜底检测。
/// 心率需 Apple Watch 记录；无表 / 无数据时返回空，检测自动退回纯动作。
@MainActor
final class HealthService {
    private let store = HKHealthStore()

    var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    func requestAuthorization() {
        guard isAvailable else { return }
        var read: Set<HKObjectType> = []
        if let hr = HKObjectType.quantityType(forIdentifier: .heartRate) { read.insert(hr) }
        if let resting = HKObjectType.quantityType(forIdentifier: .restingHeartRate) { read.insert(resting) }
        store.requestAuthorization(toShare: [], read: read) { _, _ in }
    }

    /// [from, to] 的心率样本（bpm，按时间升序）。
    func heartRateSamples(from: Date, to: Date) async -> [HeartRateSample] {
        guard isAvailable, let hrType = HKQuantityType.quantityType(forIdentifier: .heartRate) else { return [] }
        let predicate = HKQuery.predicateForSamples(withStart: from, end: to, options: .strictStartDate)
        let sort = [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)]
        return await withCheckedContinuation { (cont: CheckedContinuation<[HeartRateSample], Never>) in
            let query = HKSampleQuery(
                sampleType: hrType, predicate: predicate,
                limit: HKObjectQueryNoLimit, sortDescriptors: sort
            ) { _, samples, _ in
                let unit = HKUnit.count().unitDivided(by: .minute())
                let mapped: [HeartRateSample] = (samples as? [HKQuantitySample] ?? []).map {
                    HeartRateSample(timestamp: $0.startDate, bpm: $0.quantity.doubleValue(for: unit))
                }
                cont.resume(returning: mapped)
            }
            store.execute(query)
        }
    }

    /// 最近 14 天的静息心率；无数据回退 60。
    func restingHeartRate(asOf date: Date) async -> Double {
        guard isAvailable, let type = HKQuantityType.quantityType(forIdentifier: .restingHeartRate) else { return 60 }
        let predicate = HKQuery.predicateForSamples(withStart: date.addingTimeInterval(-14 * 24 * 3600), end: date, options: [])
        let sort = [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)]
        return await withCheckedContinuation { (cont: CheckedContinuation<Double, Never>) in
            let query = HKSampleQuery(
                sampleType: type, predicate: predicate,
                limit: 1, sortDescriptors: sort
            ) { _, samples, _ in
                let unit = HKUnit.count().unitDivided(by: .minute())
                let bpm = (samples as? [HKQuantitySample])?.first?.quantity.doubleValue(for: unit) ?? 60
                cont.resume(returning: bpm)
            }
            store.execute(query)
        }
    }
}
