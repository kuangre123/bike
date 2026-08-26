import Foundation

/// 「疑似电动车」启发式的阈值常量。
/// 均为保守初值——软提示，宁可漏判不误判真骑行；上线后按用户实测数据回调。
public enum EBikeHeuristic {
    /// 最短时长（秒）：样本太少不判。
    public static let minDurationSeconds: TimeInterval = 300
    /// 移动样本均速门槛（m/s，≈ 20 km/h）：低于此速度的匀速慢骑不判。
    public static let minAvgSpeedMps = 5.6
    /// 移动样本速度变异系数（标准差/均值）上限：电动车巡航方差极小。
    public static let maxCoefficientOfVariation = 0.30
    /// 移动判定阈值（m/s，≈ 5 km/h）：低于视为停顿（等灯/推行），剔除后再算。
    public static let movingThresholdMps = 1.4
}

/// 该骑行是否「疑似电动车」：长时间、高速、且速度方差极小（电机巡航特征）。
///
/// 三条全满足才返回 true（边界取等按命中算）：
/// 1. 骑行类型且有 GPS 逐点速度样本；
/// 2. 时长 ≥ ``EBikeHeuristic/minDurationSeconds``；
/// 3. 剔除停顿样本后，移动样本 ≥ 2 个，均速 ≥ ``EBikeHeuristic/minAvgSpeedMps``，
///    变异系数 ≤ ``EBikeHeuristic/maxCoefficientOfVariation``。
///
/// 派生量：调用方每次由存储的轨迹实时计算，不落库；只有用户的排除决定才持久化。
public func isSuspectedEBike(
    activityType: ActivityType,
    durationSeconds: TimeInterval,
    speedSamplesMps: [Double]
) -> Bool {
    guard activityType == .cycling,
          durationSeconds >= EBikeHeuristic.minDurationSeconds else { return false }

    let moving = speedSamplesMps.filter { $0 > EBikeHeuristic.movingThresholdMps }
    guard moving.count >= 2 else { return false }

    let mean = moving.reduce(0, +) / Double(moving.count)
    guard mean >= EBikeHeuristic.minAvgSpeedMps else { return false }

    let variance = moving.reduce(0.0) { $0 + ($1 - mean) * ($1 - mean) } / Double(moving.count)
    return variance.squareRoot() / mean <= EBikeHeuristic.maxCoefficientOfVariation
}
