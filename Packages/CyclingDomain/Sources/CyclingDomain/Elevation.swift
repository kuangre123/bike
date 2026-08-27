import Foundation

/// 累计爬升（米）：只累加超过噪声阈值的上升段，带滞回抑制 GPS 海拔抖动。
///
/// 算法：维护「基准海拔」，新样本相对基准的变化超过 `noiseThreshold` 才生效——
/// 上升则计入爬升并更新基准，下降只更新基准；阈值内的抖动忽略。
/// 阈值默认 10 米：手机 GPS 垂直误差常达 ±5 米，峰谷差可到 10 米，取 10 保守防虚报。
/// 样本 < 2 个返回 0。
public func elevationGainMeters(altitudes: [Double], noiseThreshold: Double = 10.0) -> Double {
    guard var base = altitudes.first else { return 0 }
    var gain = 0.0
    for a in altitudes.dropFirst() {
        let delta = a - base
        if delta >= noiseThreshold {
            gain += delta
            base = a
        } else if delta <= -noiseThreshold {
            base = a
        }
    }
    return gain
}
