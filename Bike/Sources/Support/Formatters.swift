import Foundation
import CyclingDomain

/// UI 展示用的格式化工具。纯函数，无共享可变状态。
/// 文案经 `String(localized:)` 走 Localizable.xcstrings（源语言简体中文）；
/// 数字用 `.formatted()`（当前地区小数点，如德语 1,5）；日期用地区感知格式（去掉硬编码 zh_CN）。
enum Formatters {
    static func duration(_ t: TimeInterval) -> String {
        let totalMinutes = Int(t) / 60
        let h = totalMinutes / 60
        let m = totalMinutes % 60
        if h > 0 { return String(localized: "\(h) 小时 \(m) 分") }
        return String(localized: "\(m) 分")
    }

    /// 实时时钟格式（秒级跳动），码表/骑行中用：<1 小时显示「M:SS」，否则「H:MM:SS」。
    static func durationClock(_ t: TimeInterval) -> String {
        let total = max(0, Int(t))
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 { return String(format: "%d:%02d:%02d", h, m, s) }
        return String(format: "%d:%02d", m, s)
    }

    static func distance(_ meters: Double?) -> String {
        guard let meters else { return String(localized: "无路线") }
        if meters >= 1000 {
            let km = (meters / 1000).formatted(.number.precision(.fractionLength(1)))
            return String(localized: "\(km) 公里")
        }
        return String(localized: "\(Int(meters)) 米")
    }

    static func calories(_ kcal: Double?) -> String {
        guard let kcal else { return "—" }
        return String(localized: "\(Int(kcal.rounded())) 千卡")
    }

    static func carbonSaved(_ meters: Double?) -> String {
        guard let meters else { return "—" }
        let grams = meters / 1000 * 48.5
        if grams >= 1000 {
            let kg = (grams / 1000).formatted(.number.precision(.fractionLength(1)))
            return String(localized: "\(kg) 千克")
        }
        return String(localized: "\(Int(grams.rounded())) 克")
    }

    /// 均心率展示，如「132 次/分钟」；无则 nil。
    static func heartRate(_ bpm: Double?) -> String? {
        guard let bpm else { return nil }
        return String(localized: "\(Int(bpm.rounded())) 次/分钟")
    }

    static func clockTime(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .shortened)
    }

    static func dayHeader(_ date: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(date) { return String(localized: "今天") }
        if cal.isDateInYesterday(date) { return String(localized: "昨天") }
        return date.formatted(.dateTime.month().day().weekday(.wide))
    }

    static func activityLabel(_ type: ActivityType) -> String {
        switch type {
        case .walking: return String(localized: "步行")
        case .running: return String(localized: "跑步")
        case .cycling: return String(localized: "骑行")
        case .other:   return String(localized: "其他运动")
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

    static func fullDateTime(_ date: Date) -> String {
        date.formatted(.dateTime.month().day().weekday(.abbreviated).hour().minute())
    }

    static func speed(_ mps: Double?) -> String {
        guard let mps else { return "—" }
        let kmh = (mps * 3.6).formatted(.number.precision(.fractionLength(1)))
        return String(localized: "\(kmh) 公里/时")
    }

    static func pace(duration: TimeInterval, distanceMeters: Double?) -> String? {
        guard let distanceMeters, distanceMeters >= 100 else { return nil }
        let secondsPerKm = duration / (distanceMeters / 1000)
        guard secondsPerKm.isFinite, secondsPerKm > 0 else { return nil }
        let minutes = Int(secondsPerKm) / 60
        let seconds = String(format: "%02d", Int(secondsPerKm.rounded()) % 60)
        return String(localized: "\(minutes)分\(seconds)秒/公里")
    }

    static func sourceLabel(_ source: RideSource) -> String {
        switch source {
        case .motionOnly:    return String(localized: "运动历史")
        case .gpsTracked:    return String(localized: "GPS 实采")
        case .merged:        return String(localized: "运动历史 + GPS")
        case .heartRateOnly: return String(localized: "心率检测")
        case .externalImport: return String(localized: "外部设备")
        }
    }
}
