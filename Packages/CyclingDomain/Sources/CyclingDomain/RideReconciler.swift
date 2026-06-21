import Foundation

public enum RideReconciler {

    /// 两个时间区间是否重叠。
    private static func overlaps(_ aStart: Date, _ aEnd: Date, _ bStart: Date, _ bEnd: Date) -> Bool {
        aStart < bEnd && bStart < aEnd
    }

    /// 由一条 TrackedRide 计算出带 GPS 指标的 Ride；均速对该运动类型不合理则返回 nil（丢弃）。
    private static func rideFromTracked(
        _ tracked: TrackedRide,
        source: RideSource,
        confidence: Int
    ) -> Ride? {
        let distance = totalDistanceMeters(tracked.samples)
        let duration = tracked.end.timeIntervalSince(tracked.start)
        let speed = averageSpeedMps(distanceMeters: distance, duration: duration)
        guard isPlausibleSpeed(mps: speed, for: tracked.activityType) else { return nil }
        let kcal = estimateCalories(for: tracked.activityType, avgSpeedMps: speed, duration: duration)
        return Ride(
            activityType: tracked.activityType,
            start: tracked.start, end: tracked.end, source: source,
            distanceMeters: distance, avgSpeedMps: speed, calories: kcal,
            confidence: confidence, route: tracked.samples
        )
    }

    /// 对账合并基线（已切分的 MotionSegment）、实采（TrackedRide）与心率段（HRSegment）。
    /// - 重叠匹配要求**同类型**：骑行 tracked 不会与步行 motion 段合并。
    /// - 心率段与任一已得 ride 时间重叠 → 给该 ride 附均心率（增强，不重复建记录）。
    /// - 心率段未与任何 ride 重叠 → 独立判为 `.other` 运动（心率兜底检测）。
    public static func reconcile(
        motionSegments: [MotionSegment],
        trackedRides: [TrackedRide],
        heartRateSegments: [HRSegment] = [],
        minimumDuration: TimeInterval = RideDetectionPolicy.minimumRideDuration
    ) -> [Ride] {
        var rides: [Ride] = []
        let motionSegments = motionSegments.filter { $0.duration >= minimumDuration }
        let trackedRides = trackedRides.filter { $0.end.timeIntervalSince($0.start) >= minimumDuration }
        let heartRateSegments = heartRateSegments.filter { $0.duration >= minimumDuration }

        // 1) 每条 tracked：有同类型重叠 motion 段 → merged，否则 gpsTracked；均速不合理则丢弃。
        for tracked in trackedRides {
            let overlappingConfidences = motionSegments
                .filter { $0.activityType == tracked.activityType
                    && overlaps(tracked.start, tracked.end, $0.start, $0.end) }
                .map { $0.confidence }
            let source: RideSource = overlappingConfidences.isEmpty ? .gpsTracked : .merged
            let confidence = overlappingConfidences.max() ?? 2
            if let ride = rideFromTracked(tracked, source: source, confidence: confidence) {
                rides.append(ride)
            }
        }

        // 2) 未被「保留下来的同类型 merged ride」覆盖的 motion 段 → motionOnly。
        let mergedRides = rides.filter { $0.source == .merged }
        for seg in motionSegments {
            let coveredByMerged = mergedRides.contains {
                $0.activityType == seg.activityType && overlaps($0.start, $0.end, seg.start, seg.end)
            }
            if !coveredByMerged {
                let duration = seg.end.timeIntervalSince(seg.start)
                let distance = estimatedDistanceMeters(for: seg.activityType, duration: duration)
                let speed = distance == nil ? nil : estimatedSpeedMps(for: seg.activityType)
                let kcal = estimatedCaloriesForMotionOnly(type: seg.activityType, duration: duration)
                rides.append(Ride(
                    activityType: seg.activityType,
                    start: seg.start, end: seg.end, source: .motionOnly,
                    distanceMeters: distance, avgSpeedMps: speed, calories: kcal,
                    confidence: seg.confidence
                ))
            }
        }

        // 3) 心率段与已得 ride 重叠 → 附均心率（增强）。
        rides = rides.map { ride in
            if let hr = heartRateSegments.first(where: { overlaps(ride.start, ride.end, $0.start, $0.end) }) {
                return ride.withAvgHeartRate(hr.avgBPM)
            }
            return ride
        }

        // 4) 未与任何 ride 重叠的心率段 → 独立 `.other` 运动（心率兜底）。
        for hr in heartRateSegments {
            let covered = rides.contains { overlaps($0.start, $0.end, hr.start, hr.end) }
            if covered { continue }
            let duration = hr.end.timeIntervalSince(hr.start)
            let kcal = estimateCalories(for: .other, avgSpeedMps: 0, duration: duration)
            rides.append(Ride(
                activityType: .other,
                start: hr.start, end: hr.end, source: .heartRateOnly,
                distanceMeters: nil, avgSpeedMps: nil, calories: kcal,
                confidence: 1, avgHeartRate: hr.avgBPM
            ))
        }

        return rides.sorted { $0.start < $1.start }
    }
}
