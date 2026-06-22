import SwiftUI
import CyclingDomain

/// 手表进行中运动：时长 + 心率 + 距离/速度 + 能量，可结束。
struct WatchWorkoutView: View {
    let activityType: ActivityType
    @State private var manager = WatchWorkoutManager()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(spacing: 8) {
                if let start = manager.startDate {
                    TimelineView(.periodic(from: start, by: 1)) { context in
                        Text(elapsedText(start, context.date))
                            .font(.system(.title, design: .rounded).weight(.bold))
                            .monospacedDigit()
                    }
                } else {
                    Text("--:--")
                        .font(.system(.title, design: .rounded).weight(.bold))
                }

                HStack(spacing: 6) {
                    Image(systemName: "heart.fill").foregroundStyle(.pink)
                    Text(manager.heartRate > 0 ? "\(Int(manager.heartRate))" : "--")
                        .font(.title3.weight(.bold)).monospacedDigit()
                    Text("bpm").font(.caption2).foregroundStyle(.secondary)
                }

                HStack(spacing: 16) {
                    metric(distanceText, "距离")
                    metric(speedText, "速度")
                }

                if manager.activeCalories > 0 {
                    Text("\(Int(manager.activeCalories)) 千卡")
                        .font(.caption).foregroundStyle(.secondary)
                }

                Button(role: .destructive) {
                    manager.end()
                    dismiss()
                } label: {
                    Label("结束", systemImage: "stop.fill").frame(maxWidth: .infinity)
                }
                .tint(.red)
                .padding(.top, 2)
            }
            .padding(.horizontal, 4)
        }
        .navigationTitle(Self.label(activityType))
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await manager.requestAuthorization()
            manager.start(activityType: activityType)
        }
    }

    private var distanceText: String {
        let m = manager.distanceMeters
        return m >= 1000 ? String(format: "%.2f km", m / 1000) : "\(Int(m)) m"
    }

    private var speedText: String {
        String(format: "%.1f", manager.speedMps * 3.6) + " km/h"
    }

    private func metric(_ value: String, _ title: String) -> some View {
        VStack(spacing: 1) {
            Text(value).font(.callout.weight(.bold)).monospacedDigit()
            Text(title).font(.caption2).foregroundStyle(.secondary)
        }
    }

    private func elapsedText(_ start: Date, _ now: Date) -> String {
        let total = Int(max(0, now.timeIntervalSince(start)))
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        return h > 0
            ? String(format: "%d:%02d:%02d", h, m, s)
            : String(format: "%02d:%02d", m, s)
    }

    static func label(_ t: ActivityType) -> String {
        switch t {
        case .walking: return "步行"
        case .running: return "跑步"
        case .cycling: return "骑行"
        case .other:   return "运动"
        }
    }

    static func icon(_ t: ActivityType) -> String {
        switch t {
        case .walking: return "figure.walk"
        case .running: return "figure.run"
        case .cycling: return "bicycle"
        case .other:   return "figure.mixed.cardio"
        }
    }
}
