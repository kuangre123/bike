import Foundation
import CoreMotion
import CyclingDomain

/// 查询 CoreMotion 运动历史，切分出（未过滤的）运动时段 —— 检测的「基线层」。
@MainActor
final class MotionHistoryService {
    private let activityManager = CMMotionActivityManager()

    /// 查询 [from, to] 的运动历史 → 运动时段（仅切分，过滤交给 mergeActivitySegments）。
    func activitySegments(from: Date, to: Date) async -> [MotionSegment] {
        guard CMMotionActivityManager.isActivityAvailable() else { return [] }
        let samples: [RawActivitySample] = await withCheckedContinuation { cont in
            activityManager.queryActivityStarting(from: from, to: to, to: .main) { activities, _ in
                // 回调线程内把非 Sendable 的 CMMotionActivity 映射成 Sendable 的 RawActivitySample
                let mapped = (activities ?? []).map { act in
                    RawActivitySample(
                        start: act.startDate,
                        activity: Self.activityType(of: act),
                        confidence: Self.confidenceValue(act.confidence)
                    )
                }
                cont.resume(returning: mapped)
            }
        }
        return buildActivitySegments(from: samples, queryEnd: to)
    }

    /// CMMotionActivity → ActivityType（优先级 骑行 > 跑步 > 步行；其余 nil）。
    nonisolated static func activityType(of a: CMMotionActivity) -> ActivityType? {
        if a.cycling { return .cycling }
        if a.running { return .running }
        if a.walking { return .walking }
        return nil
    }

    nonisolated static func confidenceValue(_ c: CMMotionActivityConfidence) -> Int {
        switch c {
        case .low: return 0
        case .medium: return 1
        case .high: return 2
        @unknown default: return 0
        }
    }
}
