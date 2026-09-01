import SwiftUI
import Charts
import CyclingDomain

/// [RideModel] → [RideStat] 投影：排除已标电动车的记录，按轨迹海拔算累计爬升。
enum RideStatsProjection {
    static func stats(from rides: [RideModel]) -> [RideStat] {
        rides
            .filter { !$0.excludedAsEBike }
            .map { ride in
                let alts = RideMapping.decodeRoute(ride.routeData).compactMap(\.altitude)
                let elev = alts.count >= 2 ? elevationGainMeters(altitudes: alts) : 0
                return RideStat(
                    date: ride.startDate,
                    distanceMeters: ride.distanceMeters ?? 0,
                    durationSeconds: ride.duration,
                    avgSpeedMps: ride.avgSpeedMps ?? 0,
                    elevationGainMeters: elev
                )
            }
    }
}

/// Pro「高级统计」：累计总量、连续骑行、个人记录、月度趋势。
struct AdvancedStatsView: View {
    let rides: [RideModel]

    private var stats: [RideStat] { RideStatsProjection.stats(from: rides) }
    private var totals: PeriodTotals { allTimeTotals(stats) }
    private var records: PersonalRecords { personalRecords(stats) }
    private var months: [MonthBucket] { Array(monthlyTotals(stats).suffix(12)) }
    private var currentStreak: Int {
        currentStreakDays(rideDates: stats.map(\.date), today: Date())
    }
    private var longestStreak: Int {
        longestStreakDays(rideDates: stats.map(\.date))
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                if stats.isEmpty {
                    emptyState
                } else {
                    totalsCard
                    streakCard
                    recordsCard
                    if months.count >= 2 { monthlyCard }
                }
            }
            .padding(16)
        }
        .background(FreshStatsBackground().ignoresSafeArea())
        .navigationTitle("高级统计")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "chart.bar.xaxis")
                .font(.system(size: 34, weight: .bold))
                .foregroundStyle(Color(red: 0.04, green: 0.62, blue: 0.82))
            Text("还没有可统计的骑行").font(.headline)
            Text("骑上几次，这里会出现你的记录与趋势。")
                .font(.subheadline).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 60)
    }

    // MARK: 累计总量

    private var totalsCard: some View {
        statCard(title: "累计总量") {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                metric("总次数", "\(totals.rideCount) 次", "number", .cyan)
                metric("总距离", Formatters.distance(totals.distanceMeters), "point.topleft.down.curvedto.point.bottomright.up", .mint)
                metric("总时长", Formatters.duration(totals.durationSeconds), "clock.fill", .orange)
                metric("总爬升", "\(Int(totals.elevationGainMeters)) 米", "mountain.2.fill", .purple)
            }
        }
    }

    // MARK: 连续骑行

    private var streakCard: some View {
        statCard(title: "连续骑行") {
            HStack(spacing: 12) {
                bigStat("\(currentStreak)", "当前连续（天）", .orange)
                bigStat("\(longestStreak)", "最长连续（天）", .pink)
            }
        }
    }

    // MARK: 个人记录

    private var recordsCard: some View {
        statCard(title: "个人记录") {
            VStack(spacing: 10) {
                recordRow("最远单次", Formatters.distance(records.maxDistanceMeters), "flag.checkered")
                recordRow("最久单次", Formatters.duration(records.maxDurationSeconds), "hourglass")
                recordRow("最快均速", Formatters.speed(records.maxAvgSpeedMps), "gauge.with.needle")
                recordRow("最大爬升", "\(Int(records.maxElevationGainMeters)) 米", "mountain.2")
                recordRow("单日最多", "\(records.mostRidesInADay) 次", "calendar")
            }
        }
    }

    // MARK: 月度趋势

    private var monthlyCard: some View {
        statCard(title: "月度距离趋势") {
            Chart(months) { m in
                BarMark(
                    x: .value("月", m.id),
                    y: .value("公里", m.totals.distanceMeters / 1000)
                )
                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                .foregroundStyle(
                    LinearGradient(colors: [Color(red: 0.05, green: 0.64, blue: 0.86),
                                            Color(red: 0.28, green: 0.84, blue: 0.62)],
                                   startPoint: .top, endPoint: .bottom)
                )
            }
            .chartXAxis {
                AxisMarks { value in
                    AxisValueLabel {
                        if let id = value.as(String.self) {
                            Text(String(id.suffix(2)) + "月").font(.caption2)
                        }
                    }
                }
            }
            .frame(height: 150)
        }
    }

    // MARK: 复用样式

    private func statCard<Content: View>(title: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(Color(red: 0.10, green: 0.34, blue: 0.40))
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color.white.opacity(0.82))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(Color.white.opacity(0.85), lineWidth: 1))
        .shadow(color: Color(red: 0.20, green: 0.70, blue: 0.80).opacity(0.12), radius: 14, y: 8)
    }

    private func metric(_ title: String, _ value: String, _ icon: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Image(systemName: icon)
                .font(.caption.weight(.bold)).foregroundStyle(color)
                .frame(width: 26, height: 26).background(color.opacity(0.13)).clipShape(Circle())
            Text(value).font(.headline.weight(.heavy)).lineLimit(1).minimumScaleFactor(0.6)
            Text(title).font(.caption2.weight(.medium)).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10).background(Color.white.opacity(0.6))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func bigStat(_ value: String, _ title: String, _ color: Color) -> some View {
        VStack(spacing: 4) {
            Text(value).font(.system(size: 40, weight: .black, design: .rounded))
                .foregroundStyle(color).minimumScaleFactor(0.5).lineLimit(1)
            Text(title).font(.caption.weight(.medium)).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 8)
        .background(color.opacity(0.10)).clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func recordRow(_ title: String, _ value: String, _ icon: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon).font(.subheadline.weight(.bold))
                .foregroundStyle(Color(red: 0.04, green: 0.62, blue: 0.82)).frame(width: 24)
            Text(title).font(.subheadline)
            Spacer()
            Text(value).font(.subheadline.weight(.heavy)).foregroundStyle(.primary)
        }
    }
}

private struct FreshStatsBackground: View {
    var body: some View {
        LinearGradient(
            colors: [Color(red: 0.83, green: 0.97, blue: 1.00),
                     Color(red: 0.93, green: 1.00, blue: 0.95),
                     Color(red: 1.00, green: 0.99, blue: 0.90)],
            startPoint: .topLeading, endPoint: .bottomTrailing
        )
    }
}
