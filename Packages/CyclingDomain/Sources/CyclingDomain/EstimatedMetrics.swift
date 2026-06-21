import Foundation

/// Conservative fallback speeds for records that have CoreMotion activity but no GPS route.
public func estimatedSpeedMps(for type: ActivityType) -> Double {
    switch type {
    case .walking: return 4.5 / 3.6
    case .running: return 9.0 / 3.6
    case .cycling: return 6.5 / 3.6
    case .other: return 0
    }
}

public func estimatedDistanceMeters(for type: ActivityType, duration: TimeInterval) -> Double? {
    guard duration > 0, type != .other else { return nil }
    return estimatedSpeedMps(for: type) * duration
}

public func estimatedCaloriesForMotionOnly(type: ActivityType, duration: TimeInterval) -> Double? {
    guard duration > 0, type != .other else { return nil }
    return estimateCalories(for: type, avgSpeedMps: estimatedSpeedMps(for: type), duration: duration)
}
