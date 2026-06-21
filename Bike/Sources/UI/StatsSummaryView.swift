import SwiftUI
import Charts

/// 本周概览（次数/时长/距离）+ 近 7 天每日运动分钟柱状趋势。
struct StatsSummaryView: View {
    let rides: [RideModel]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 8) {
                stat("本周运动", "\(weekRides.count) 次", "figure.outdoor.cycle")
                stat("总时长", Formatters.duration(totalDuration), "clock.fill")
                stat("总距离", totalDistanceText, "point.topleft.down.curvedto.point.bottomright.up")
            }

            Chart(last7Days) { bar in
                BarMark(
                    x: .value("日", bar.label),
                    y: .value("分钟", bar.minutes)
                )
                .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                .foregroundStyle(
                    LinearGradient(
                        colors: [
                            Color(red: 0.05, green: 0.64, blue: 0.86),
                            Color(red: 0.28, green: 0.84, blue: 0.62)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
            }
            .chartYAxis(.hidden)
            .chartXAxis {
                AxisMarks { _ in
                    AxisValueLabel()
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(height: 112)
        }
        .padding(16)
        .background(Color.white.opacity(0.78))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.white.opacity(0.85), lineWidth: 1)
        )
        .shadow(color: Color(red: 0.20, green: 0.70, blue: 0.80).opacity(0.12), radius: 14, y: 8)
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

    private func stat(_ title: String, _ value: String, _ icon: String) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Image(systemName: icon)
                .font(.caption.weight(.bold))
                .foregroundStyle(Color(red: 0.04, green: 0.61, blue: 0.78))
                .frame(width: 24, height: 24)
                .background(Color(red: 0.04, green: 0.68, blue: 0.82).opacity(0.12))
                .clipShape(Circle())
            Text(value)
                .font(.subheadline.weight(.heavy))
                .lineLimit(1)
                .minimumScaleFactor(0.66)
            Text(title)
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Color.white.opacity(0.62))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}
