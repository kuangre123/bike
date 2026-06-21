import Foundation

/// 合并时间相邻且**同类型**的运动时段，并丢弃合并后短于 minDuration 的结果。
/// - 输入无需有序；内部按 start 排序。
/// - 合并后时段置信度取参与合并各段的最大值。
public func mergeActivitySegments(
    _ segments: [MotionSegment],
    maxGap: TimeInterval,
    minDuration: TimeInterval,
    gapForType: ((ActivityType) -> TimeInterval)? = nil,
    minDurationForType: ((ActivityType) -> TimeInterval)? = nil
) -> [MotionSegment] {
    let sorted = segments.sorted { $0.start < $1.start }
    var result: [MotionSegment] = []
    for seg in sorted {
        let allowedGap = gapForType?(seg.activityType) ?? maxGap
        if let last = result.last,
           last.activityType == seg.activityType,
           seg.start.timeIntervalSince(last.end) <= allowedGap {
            result[result.count - 1] = MotionSegment(
                activityType: last.activityType,
                start: last.start,
                end: max(last.end, seg.end),
                confidence: max(last.confidence, seg.confidence)
            )
        } else {
            result.append(seg)
        }
    }
    return result.filter { $0.duration >= (minDurationForType?($0.activityType) ?? minDuration) }
}
