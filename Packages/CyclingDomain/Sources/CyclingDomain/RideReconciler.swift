import Foundation

public enum RideReconciler {

    /// 两个时间区间是否重叠。
    private static func overlaps(_ aStart: Date, _ aEnd: Date, _ bStart: Date, _ bEnd: Date) -> Bool {
        aStart < bEnd && bStart < aEnd
    }

    /// 由一条 TrackedRide 计算出带 GPS 指标的 Ride；均速不合理返回 nil（丢弃）。
    private static func rideFromTracked(
        _ tracked: TrackedRide,
        source: RideSource,
        confidence: Int
    ) -> Ride? {
        let distance = totalDistanceMeters(tracked.samples)
        let duration = tracked.end.timeIntervalSince(tracked.start)
        let speed = averageSpeedMps(distanceMeters: distance, duration: duration)
        guard isPlausibleCyclingSpeed(mps: speed) else { return nil }
        let kcal = estimateCalories(avgSpeedMps: speed, duration: duration)
        return Ride(
            start: tracked.start, end: tracked.end, source: source,
            distanceMeters: distance, avgSpeedMps: speed, calories: kcal,
            confidence: confidence
        )
    }

    /// 对账合并基线与实采。
    public static func reconcile(
        motionSegments: [MotionSegment],
        trackedRides: [TrackedRide]
    ) -> [Ride] {
        var rides: [Ride] = []

        // 1) 每条 tracked：有重叠 motion 段 → merged，否则 gpsTracked；均速不合理则丢弃。
        for tracked in trackedRides {
            let overlappingConfidences = motionSegments
                .filter { overlaps(tracked.start, tracked.end, $0.start, $0.end) }
                .map { $0.confidence }
            let source: RideSource = overlappingConfidences.isEmpty ? .gpsTracked : .merged
            let confidence = overlappingConfidences.max() ?? 2
            if let ride = rideFromTracked(tracked, source: source, confidence: confidence) {
                rides.append(ride)
            }
        }

        // 2) 未被「保留下来的 merged ride」覆盖的 motion 段 → motionOnly。
        //    （被丢弃的 tracked 不会产生 merged ride，其对应 motion 段会在此退化为 motionOnly。）
        let mergedRanges = rides.filter { $0.source == .merged }.map { ($0.start, $0.end) }
        for seg in motionSegments {
            let coveredByMerged = mergedRanges.contains { overlaps($0.0, $0.1, seg.start, seg.end) }
            if !coveredByMerged {
                rides.append(Ride(
                    start: seg.start, end: seg.end, source: .motionOnly,
                    distanceMeters: nil, avgSpeedMps: nil, calories: nil,
                    confidence: seg.confidence
                ))
            }
        }

        return rides.sorted { $0.start < $1.start }
    }
}
