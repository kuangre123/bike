import SwiftUI

/// 首页「本周目标」进度卡。免费功能。goalKm <= 0 时调用方不应展示。
/// 「本周」按日历周（尊重地区首日）计，只统计未排除记录的距离。
struct WeeklyGoalCard: View {
    let rides: [RideModel]
    let goalKm: Double

    private var weekStart: Date {
        Calendar.current.dateInterval(of: .weekOfYear, for: Date())?.start ?? Date()
    }
    private var doneKm: Double {
        rides
            .filter { $0.startDate >= weekStart }
            .reduce(0.0) { $0 + ($1.distanceMeters ?? 0) } / 1000
    }
    private var progress: Double { goalKm > 0 ? min(1, doneKm / goalKm) : 0 }
    private var reached: Bool { doneKm >= goalKm && goalKm > 0 }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("本周目标", systemImage: "target")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(Color(red: 0.10, green: 0.34, blue: 0.40))
                Spacer()
                Text(reached ? "已达成 🎉" : String(format: "%.1f / %.0f 公里", doneKm, goalKm))
                    .font(.caption.weight(.heavy))
                    .foregroundStyle(reached ? Color(red: 0.18, green: 0.66, blue: 0.46) : .secondary)
                    .contentTransition(.numericText())
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.black.opacity(0.06)).frame(height: 12)
                    Capsule()
                        .fill(LinearGradient(
                            colors: reached
                                ? [Color(red: 0.22, green: 0.78, blue: 0.55), Color(red: 0.18, green: 0.66, blue: 0.46)]
                                : [Color(red: 0.05, green: 0.64, blue: 0.86), Color(red: 0.28, green: 0.84, blue: 0.62)],
                            startPoint: .leading, endPoint: .trailing))
                        .frame(width: max(12, geo.size.width * progress), height: 12)
                        .animation(.easeOut(duration: 0.4), value: progress)
                }
            }
            .frame(height: 12)

            if !reached {
                Text(String(format: "还差 %.1f 公里", max(0, goalKm - doneKm)))
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .background(Color.white.opacity(0.82))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(Color.white.opacity(0.85), lineWidth: 1))
        .shadow(color: Color(red: 0.20, green: 0.70, blue: 0.80).opacity(0.12), radius: 14, y: 8)
    }
}
