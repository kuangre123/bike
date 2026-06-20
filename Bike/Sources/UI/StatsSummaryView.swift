import SwiftUI
import Charts

/// 本周概览（次数/时长/距离）+ 近 7 天每日运动分钟柱状趋势。
struct StatsSummaryView: View {
    let rides: [RideModel]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                stat("本周运动", "\(weekRides.count) 次")
                Spacer()
                stat("总时长", Formatters.duration(totalDuration))
                Spacer()
                stat("总距离", totalDistanceText)
            }

            Chart(last7Days) { bar in
                BarMark(
                    x: .value("日", bar.label),
                    y: .value("分钟", bar.minutes)
                )
                .foregroundStyle(.tint)
            }
            .frame(height: 110)
        }
        .padding(.vertical, 4)
    }

    // MARK: 计算

    private var weekRides: [RideModel] {
        let cutoff = Calendar.current.date(byAdding: .day, value: -7, to: Date())!
        return rides.filter { $0.startDate >= cutoff }
    }

    private var totalDuration: TimeInterval { weekRides.reduce(0) { $0 + $1.duration } }

    private var totalDistanceText: String {
        let meters = weekRides.reduce(0.0) { $0 + ($1.distanceMeters ?? 0) }
        if meters >= 1000 { return String(format: "%.1f 公里", meters / 1000) }
        return "\(Int(meters)) 米"
    }

    private struct DayBar: Identifiable {
        let id = UUID()
        let label: String
        let minutes: Double
    }

    private var last7Days: [DayBar] {
        let cal = Calendar.current
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "zh_CN")
        fmt.dateFormat = "E"
        return (0..<7).reversed().map { offset in
            let day = cal.date(byAdding: .day, value: -offset, to: cal.startOfDay(for: Date()))!
            let next = cal.date(byAdding: .day, value: 1, to: day)!
            let minutes = rides
                .filter { $0.startDate >= day && $0.startDate < next }
                .reduce(0.0) { $0 + $1.duration } / 60
            return DayBar(label: fmt.string(from: day), minutes: minutes)
        }
    }

    private func stat(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.headline)
            Text(title).font(.caption).foregroundStyle(.secondary)
        }
    }
}
