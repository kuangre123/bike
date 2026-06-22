import SwiftUI
import CyclingDomain

/// 手表表盘式首页：中央大圆点击直接开始骑行；下方次级类型 + 今日概览（手机同步）。
struct WatchHomeView: View {
    @Environment(WatchConnectivityProvider.self) private var connectivity

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

                    if let summary = connectivity.today {
                        todayCard(summary)
                    }
                }
                .padding(.vertical, 6)
            }
            .navigationTitle("快乐轻骑")
        }
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
