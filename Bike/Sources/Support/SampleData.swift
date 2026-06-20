#if DEBUG
import Foundation
import CyclingDomain

/// 调试用示例运动 —— M3 真实检测接上前，用来在 Xcode 模拟器里看 UI。
enum SampleData {
    static func rides(now: Date = Date()) -> [Ride] {
        let cal = Calendar.current
        func at(_ daysAgo: Int, _ hour: Int, _ minute: Int) -> Date {
            let base = cal.date(byAdding: .day, value: -daysAgo, to: now)!
            return cal.date(bySettingHour: hour, minute: minute, second: 0, of: base)!
        }
        return [
            Ride(activityType: .cycling, start: at(0, 8, 12), end: at(0, 8, 27), source: .merged,
                 distanceMeters: 4200, avgSpeedMps: 4200 / (15 * 60), calories: 95, confidence: 2),
            Ride(activityType: .walking, start: at(0, 12, 30), end: at(0, 12, 44), source: .motionOnly,
                 distanceMeters: nil, avgSpeedMps: nil, calories: nil, confidence: 1),
            Ride(activityType: .running, start: at(1, 7, 0), end: at(1, 7, 32), source: .merged,
                 distanceMeters: 5200, avgSpeedMps: 5200 / (32 * 60), calories: 320, confidence: 2),
            Ride(activityType: .cycling, start: at(2, 17, 20), end: at(2, 17, 31), source: .merged,
                 distanceMeters: 3100, avgSpeedMps: 3100 / (11 * 60), calories: 70, confidence: 2),
            // 心率兜底检测出的「其他运动」（如器械训练）：无位移、无路线，靠心率
            Ride(activityType: .other, start: at(0, 20, 5), end: at(0, 20, 48), source: .heartRateOnly,
                 distanceMeters: nil, avgSpeedMps: nil, calories: 251, confidence: 1, avgHeartRate: 138),
        ]
    }
}
#endif
