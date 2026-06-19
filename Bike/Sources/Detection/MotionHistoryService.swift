import Foundation
import CoreMotion
import CyclingDomain

/// 查询 CoreMotion 运动历史，切分出（未过滤的）骑行时段 —— 检测的「基线层」。
/// 标 @MainActor：在主线程发起查询；查询回调在内部 queue，立即映射为 Sendable 类型后再跨界。
@MainActor
final class MotionHistoryService {
    private let activityManager = CMMotionActivityManager()
    private let queue = OperationQueue()

    /// 查询 [from, to] 的运动历史 → 骑行时段（仅切分，过滤交给 mergeCyclingSegments）。
    func cyclingSegments(from: Date, to: Date) async -> [MotionSegment] {
        guard CMMotionActivityManager.isActivityAvailable() else { return [] }
        let samples: [RawActivitySample] = await withCheckedContinuation { cont in
            activityManager.queryActivityStarting(from: from, to: to, to: queue) { activities, _ in
                // 在回调线程内把非 Sendable 的 CMMotionActivity 映射成 Sendable 的 RawActivitySample
                let mapped = (activities ?? []).map { act in
                    RawActivitySample(
                        start: act.startDate,
                        isCycling: act.cycling,
                        confidence: Self.confidenceValue(act.confidence)
                    )
                }
                cont.resume(returning: mapped)
            }
        }
        return buildCyclingSegments(from: samples, queryEnd: to)
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
