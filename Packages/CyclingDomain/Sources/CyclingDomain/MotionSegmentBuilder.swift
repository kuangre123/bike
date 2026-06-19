import Foundation

/// 运动分类器的一条原始活动样本 —— `CMMotionActivity` 的简化投影，便于纯逻辑测试。
/// 每条样本代表「从 `start` 起、直到下一条样本 `start`」期间的活动状态。
public struct RawActivitySample: Equatable, Sendable {
    public let start: Date
    public let isCycling: Bool
    public let confidence: Int   // 0=low, 1=medium, 2=high
    public init(start: Date, isCycling: Bool, confidence: Int) {
        self.start = start
        self.isCycling = isCycling
        self.confidence = confidence
    }
}

/// 把（可乱序的）原始活动样本切分成连续骑行时段。
/// - 末尾若仍处于骑行，以 `queryEnd` 收尾。
/// - 连续骑行段的置信度取段内最大值。
/// - 不做最小时长 / 间隔过滤 —— 那交给 `mergeCyclingSegments`。
public func buildCyclingSegments(from samples: [RawActivitySample], queryEnd: Date) -> [MotionSegment] {
    let sorted = samples.sorted { $0.start < $1.start }
    var segments: [MotionSegment] = []
    var segStart: Date? = nil
    var segConfidence = 0
    for sample in sorted {
        if sample.isCycling {
            if segStart == nil {
                segStart = sample.start
                segConfidence = sample.confidence
            } else {
                segConfidence = max(segConfidence, sample.confidence)
            }
        } else if let start = segStart {
            segments.append(MotionSegment(start: start, end: sample.start, confidence: segConfidence))
            segStart = nil
            segConfidence = 0
        }
    }
    if let start = segStart, start < queryEnd {
        segments.append(MotionSegment(start: start, end: queryEnd, confidence: segConfidence))
    }
    return segments
}
