import Foundation
import CyclingDomain

/// UI 展示用的格式化工具。纯函数，无共享可变状态。
enum Formatters {
    static func duration(_ t: TimeInterval) -> String {
        let totalMinutes = Int(t) / 60
        let h = totalMinutes / 60
        let m = totalMinutes % 60
        if h > 0 { return "\(h) 小时 \(m) 分" }
        return "\(m) 分"
    }

    static func distance(_ meters: Double?) -> String {
        guard let meters else { return "无路线" }
        if meters >= 1000 {
            return String(format: "%.1f 公里", meters / 1000)
        }
        return "\(Int(meters)) 米"
    }

    static func calories(_ kcal: Double?) -> String {
        guard let kcal else { return "—" }
        return "\(Int(kcal.rounded())) 千卡"
    }

    /// 均心率展示，如「♥ 132」；无则 nil。
    static func heartRate(_ bpm: Double?) -> String? {
        guard let bpm else { return nil }
        return "♥ \(Int(bpm.rounded()))"
    }

    static func clockTime(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f.string(from: date)
    }

    static func dayHeader(_ date: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(date) { return "今天" }
        if cal.isDateInYesterday(date) { return "昨天" }
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "M月d日 EEEE"
        return f.string(from: date)
    }

    static func activityLabel(_ type: ActivityType) -> String {
        switch type {
        case .walking: return "步行"
        case .running: return "跑步"
        case .cycling: return "骑行"
        case .other:   return "其他运动"
        }
    }

    static func activityIcon(_ type: ActivityType) -> String {
        switch type {
        case .walking: return "figure.walk"
        case .running: return "figure.run"
        case .cycling: return "bicycle"
        case .other:   return "figure.mixed.cardio"
        }
    }
}
