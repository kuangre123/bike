#if DEBUG
import Foundation
import CyclingDomain

/// 调试用示例骑行 —— M3 真实检测接上前，用来在 Xcode 模拟器里看 UI。
enum SampleData {
    static func rides(now: Date = Date()) -> [Ride] {
        let cal = Calendar.current
        func at(_ daysAgo: Int, _ hour: Int, _ minute: Int) -> Date {
            let base = cal.date(byAdding: .day, value: -daysAgo, to: now)!
            return cal.date(bySettingHour: hour, minute: minute, second: 0, of: base)!
        }
        return [
            Ride(start: at(0, 8, 12), end: at(0, 8, 27), source: .merged,
                 distanceMeters: 4200, avgSpeedMps: 4200 / (15 * 60), calories: 95, confidence: 2),
            Ride(start: at(0, 18, 40), end: at(0, 18, 46), source: .motionOnly,
                 distanceMeters: nil, avgSpeedMps: nil, calories: nil, confidence: 1),
            Ride(start: at(1, 9, 5), end: at(1, 9, 33), source: .merged,
                 distanceMeters: 8600, avgSpeedMps: 8600 / (28 * 60), calories: 210, confidence: 2),
            Ride(start: at(2, 17, 20), end: at(2, 17, 31), source: .merged,
                 distanceMeters: 3100, avgSpeedMps: 3100 / (11 * 60), calories: 70, confidence: 2),
        ]
    }
}
#endif
