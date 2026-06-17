import Foundation

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
}
