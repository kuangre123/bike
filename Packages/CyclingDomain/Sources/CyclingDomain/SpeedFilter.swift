import Foundation

/// 均速是否落在合理骑行区间（约 8–35 km/h，边界含）。
public func isPlausibleCyclingSpeed(
    mps: Double,
    minKmh: Double = 8,
    maxKmh: Double = 35
) -> Bool {
    let kmh = mps * 3.6
    return kmh >= minKmh && kmh <= maxKmh
}
