import Foundation

/// 合并时间上相邻（间隔 <= maxGap）的骑行时段，并丢弃合并后短于 minDuration 的结果。
/// - 输入无需有序；内部按 start 排序。
/// - 合并后时段的置信度取参与合并各段的最大值。
public func mergeCyclingSegments(
    _ segments: [MotionSegment],
    maxGap: TimeInterval,
    minDuration: TimeInterval
) -> [MotionSegment] {
    let sorted = segments.sorted { $0.start < $1.start }
    var result: [MotionSegment] = []
    for seg in sorted {
        if let last = result.last, seg.start.timeIntervalSince(last.end) <= maxGap {
            result[result.count - 1] = MotionSegment(
                start: last.start,
                end: max(last.end, seg.end),
                confidence: max(last.confidence, seg.confidence)
            )
        } else {
            result.append(seg)
        }
    }
    return result.filter { $0.duration >= minDuration }
}
