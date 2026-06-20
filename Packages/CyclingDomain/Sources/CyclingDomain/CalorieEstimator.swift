import Foundation

/// 按运动类型与均速估算 MET 值（Compendium of Physical Activities 近似）。
public func metsFor(_ type: ActivityType, avgSpeedMps: Double) -> Double {
    let kmh = avgSpeedMps * 3.6
    switch type {
    case .walking:
        switch kmh {
        case ..<4:   return 2.8
        case ..<5.5: return 3.5
        default:     return 4.3
        }
    case .running:
        switch kmh {
        case ..<8:   return 8.0
        case ..<11:  return 10.0
        case ..<14:  return 12.0
        default:     return 14.0
        }
    case .cycling:
        switch kmh {
        case ..<16:  return 4.0
        case ..<19:  return 6.0
        case ..<22:  return 8.0
        case ..<25:  return 10.0
        default:     return 12.0
        }
    case .other:
        return 5.0   // 无速度可依（心率兜底检测），取通用中等强度
    }
}

/// 估算消耗卡路里：kcal = METs × 体重kg × 小时。
public func estimateCalories(
    for type: ActivityType,
    avgSpeedMps: Double,
    duration: TimeInterval,
    weightKg: Double = 70
) -> Double {
    metsFor(type, avgSpeedMps: avgSpeedMps) * weightKg * (duration / 3600)
}
