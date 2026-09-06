import SwiftUI
import CyclingDomain

/// 手表表盘式首页：中央大圆点击直接开始骑行；下方次级类型 + 心率 + 今日概览（手机同步）。
struct WatchHomeView: View {
    @Environment(WatchConnectivityProvider.self) private var connectivity
    @Environment(WatchHeartRateMonitor.self) private var heartRate
    @State private var now = Date()

    private let clock = Timer.publish(every: 5, on: .main, in: .common).autoconnect()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    NavigationLink {
                        WatchWorkoutView(activityType: .cycling)
                    } label: {
                        centerDial
                    }
                    .buttonStyle(.plain)

                    HStack(spacing: 8) {
                        secondary(.running)
                        secondary(.walking)
                        secondary(.other)
                    }

                    heartRateCard

                    if let summary = connectivity.today {
                        todayCard(summary)
                    }
                }
                .padding(.vertical, 6)
            }
            .navigationTitle("快乐轻骑")
        }
        .onReceive(clock) { now = $0 }
    }

    /// 心率卡片。没授权过时是一个按钮，点了才请求（和运动页一样不主动弹窗）。
    @ViewBuilder
    private var heartRateCard: some View {
        if heartRate.needsPermission {
            Button {
                Task { await heartRate.requestAndStart() }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "heart.fill").font(.caption).foregroundStyle(Color.pink)
                    Text("开启心率").font(.footnote.weight(.semibold))
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right").font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(Color.gray.opacity(0.15))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            .buttonStyle(.plain)
        } else {
            heartRateReadout
        }
    }

    /// 手表不在运动中时几分钟才被动测一次，所以如实标出「最近」和测量时间，
    /// 不把几分钟前的旧值当成实时心率；没读到就显示「--」，不做推算。
    private var heartRateReadout: some View {
        let reading = heartRate.latest
        let freshness = reading?.freshness(at: now) ?? .stale
        let usable = freshness != .stale ? reading : nil
        return HStack(spacing: 6) {
            Image(systemName: "heart.fill")
                .font(.caption)
                .foregroundStyle(usable == nil ? Color.secondary : Color.pink)
            Text(usable.map { "\(Int($0.bpm.rounded()))" } ?? "--")
                .font(.title3.weight(.bold))
                .monospacedDigit()
            Text("bpm")
                .font(.caption2)
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
            Text(caption(for: usable, freshness: freshness))
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color.gray.opacity(0.15))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func caption(for reading: WatchHeartRate?, freshness: WatchHeartRateFreshness) -> String {
        guard let reading else { return "等待心率" }
        if freshness == .live { return "实时" }
        let minutes = Int(now.timeIntervalSince(reading.measuredAt) / 60)
        return minutes <= 0 ? "刚刚" : "\(minutes) 分钟前"
    }

    private var centerDial: some View {
        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.04, green: 0.68, blue: 0.86),
                            Color(red: 0.22, green: 0.82, blue: 0.55)
                        ],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    )
                )
            VStack(spacing: 3) {
                Image(systemName: "bicycle").font(.system(size: 32, weight: .bold))
                Text("开始骑行").font(.footnote.weight(.heavy))
            }
            .foregroundStyle(.white)
        }
        .frame(width: 130, height: 130)
        .shadow(color: .cyan.opacity(0.35), radius: 8, y: 3)
    }

    private func secondary(_ type: ActivityType) -> some View {
        NavigationLink {
            WatchWorkoutView(activityType: type)
        } label: {
            VStack(spacing: 3) {
                Image(systemName: WatchWorkoutView.icon(type)).font(.body.weight(.bold))
                Text(WatchWorkoutView.label(type)).font(.caption2)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 9)
            .background(Color.gray.opacity(0.22))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func todayCard(_ summary: WatchDaySummary) -> some View {
        let minutes = Int(summary.durationSeconds / 60)
        return Text("今日 \(summary.count) 次 · \(minutes) 分钟")
            .font(.caption2)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity)
            .padding(8)
            .background(Color.gray.opacity(0.15))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}
