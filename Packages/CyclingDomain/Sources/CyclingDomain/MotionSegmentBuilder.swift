import Foundation

/// 运动分类器的一条原始活动样本 —— `CMMotionActivity` 的简化投影，便于纯逻辑测试。
/// 每条样本代表「从 `start` 起、直到下一条样本 `start`」期间的活动状态。
/// `activity == nil` 表示静止 / 驾车 / 未知（非记录目标）。
public struct RawActivitySample: Equatable, Sendable {
    public let start: Date
    public let activity: ActivityType?
    public let confidence: Int   // 0=low, 1=medium, 2=high
    public init(start: Date, activity: ActivityType?, confidence: Int) {
        self.start = start
        self.activity = activity
        self.confidence = confidence
    }
}

/// 把（可乱序的）原始活动样本切分成连续的同类型运动时段。
/// - 活动类型变化（含切到 nil）即收尾当前段。
/// - 末尾若仍处于某活动，以 `queryEnd` 收尾。
/// - 连续同类型段的置信度取段内最大值。
/// - 不做最小时长 / 间隔过滤 —— 那交给 `mergeActivitySegments`。
public func buildActivitySegments(from samples: [RawActivitySample], queryEnd: Date) -> [MotionSegment] {
    let sorted = samples.sorted { $0.start < $1.start }
    var segments: [MotionSegment] = []
    var curType: ActivityType? = nil
    var curStart: Date? = nil
    var curConfidence = 0

    func closeCurrent(end: Date) {
        if let type = curType, let start = curStart, start < end {
            segments.append(MotionSegment(activityType: type, start: start, end: end, confidence: curConfidence))
        }
    }

    for sample in sorted {
        if sample.activity == curType {
            if curType != nil { curConfidence = max(curConfidence, sample.confidence) }
        } else {
            closeCurrent(end: sample.start)
            curType = sample.activity
            curStart = sample.activity == nil ? nil : sample.start
            curConfidence = sample.confidence
        }
    }
    closeCurrent(end: queryEnd)
    return segments
}
