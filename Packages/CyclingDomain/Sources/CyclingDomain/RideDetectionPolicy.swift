import Foundation

public enum RideDetectionPolicy {
    /// Ignore very short activities to avoid logging accidental movement bursts.
    public static let minimumRideDuration: TimeInterval = 2 * 60

    /// Short gaps are normal for walking/running because CoreMotion can briefly report unknown.
    public static let defaultMotionMergeGap: TimeInterval = 60

    /// Cycling is often reported in sparse bursts when the phone is in a pocket or mounted on a shared bike.
    public static let cyclingMotionMergeGap: TimeInterval = 20 * 60

    public static func motionMergeGap(for activityType: ActivityType) -> TimeInterval {
        activityType == .cycling ? cyclingMotionMergeGap : defaultMotionMergeGap
    }

    /// 步行噪声多（等红灯、室内走动、短距挪动），要求更长时间才记录。
    public static let walkingMinimumDuration: TimeInterval = 5 * 60

    /// 各运动类型的最小记录时长。步行 5 分钟，其余沿用 `minimumRideDuration`。
    public static func minimumDuration(for activityType: ActivityType) -> TimeInterval {
        activityType == .walking ? walkingMinimumDuration : minimumRideDuration
    }
}
