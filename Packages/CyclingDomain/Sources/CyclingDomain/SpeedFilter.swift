import Foundation

/// 均速是否落在该运动类型的合理区间（边界含），用于过滤误判（如把驾车当骑行）。
public func isPlausibleSpeed(mps: Double, for type: ActivityType) -> Bool {
    let kmh = mps * 3.6
    let bounds: (min: Double, max: Double)
    switch type {
    case .walking: bounds = (1.5, 9)
    case .running: bounds = (5, 22)
    case .cycling: bounds = (8, 40)
    case .other:   bounds = (0, .infinity)   // 心率兜底，不做速度门槛
    }
    return kmh >= bounds.min && kmh <= bounds.max
}
