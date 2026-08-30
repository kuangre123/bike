import Foundation
import CyclingDomain

/// 「自动记录哪些运动类型」用户偏好。默认全部记录，可逐项关闭。
///
/// 只作用于**被动自动检测**的记录；手动开始的骑行是用户主动行为，始终保存。
/// 跑步、骑行视为核心运动不提供关闭。电动车不是独立类型，而是「疑似电动车」的骑行——
/// 关掉后，自动检测到的疑似电动车骑行直接不保存（有 GPS 轨迹才判得出；无轨迹保守保留）。
enum ActivityRecordingPreferences {
    static let recordWalkingKey = "recordWalking"
    static let recordEBikeKey = "recordEBike"
    static let recordOtherKey = "recordOther"

    static var recordWalking: Bool { flag(recordWalkingKey) }
    static var recordEBike: Bool { flag(recordEBikeKey) }
    static var recordOther: Bool { flag(recordOtherKey) }

    private static func flag(_ key: String) -> Bool {
        UserDefaults.standard.object(forKey: key) as? Bool ?? true
    }

    /// 该自动检测到的运动是否应保存。读当前偏好。
    static func shouldRecord(_ ride: Ride) -> Bool {
        shouldRecord(
            activityType: ride.activityType,
            durationSeconds: ride.duration,
            speedSamplesMps: (ride.route ?? []).map(\.speedMps),
            recordWalking: recordWalking,
            recordEBike: recordEBike,
            recordOther: recordOther
        )
    }

    /// 纯决策，可单测。
    static func shouldRecord(
        activityType: ActivityType,
        durationSeconds: TimeInterval,
        speedSamplesMps: [Double],
        recordWalking: Bool,
        recordEBike: Bool,
        recordOther: Bool
    ) -> Bool {
        switch activityType {
        case .walking: return recordWalking
        case .other:   return recordOther
        case .running: return true
        case .cycling:
            if !recordEBike,
               isSuspectedEBike(activityType: .cycling,
                                durationSeconds: durationSeconds,
                                speedSamplesMps: speedSamplesMps) {
                return false
            }
            return true
        }
    }
}
