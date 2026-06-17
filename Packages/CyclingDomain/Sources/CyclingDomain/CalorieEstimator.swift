import Foundation

/// 骑行 MET 值，按均速分档（Compendium of Physical Activities 近似）。
public func cyclingMETs(avgSpeedMps: Double) -> Double {
    let kmh = avgSpeedMps * 3.6
    switch kmh {
    case ..<16: return 4.0
    case ..<19: return 6.0
    case ..<22: return 8.0
    case ..<25: return 10.0
    default:    return 12.0
    }
}

/// 估算消耗卡路里：kcal = METs × 体重kg × 小时。
public func estimateCalories(
    avgSpeedMps: Double,
    duration: TimeInterval,
    weightKg: Double = 70
) -> Double {
    let hours = duration / 3600
    return cyclingMETs(avgSpeedMps: avgSpeedMps) * weightKg * hours
}
