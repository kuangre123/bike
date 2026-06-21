import SwiftUI
import CyclingDomain

/// 手表首页：今日概览（手机同步）+ 选运动类型开始记录（采心率）。
struct WatchHomeView: View {
    @Environment(WatchConnectivityProvider.self) private var connectivity
    private let types: [ActivityType] = [.cycling, .running, .walking, .other]

    var body: some View {
        NavigationStack {
            List {
                if let summary = connectivity.today {
                    Section("今日") {
                        LabeledContent("运动", value: "\(summary.count) 次")
                        LabeledContent("时长", value: Self.durationText(summary.durationSeconds))
                        if summary.distanceMeters > 0 {
                            LabeledContent("距离", value: Self.distanceText(summary.distanceMeters))
                        }
                    }
                }

                Section("开始记录") {
                    ForEach(types, id: \.self) { type in
                        NavigationLink {
                            WatchWorkoutView(activityType: type)
                        } label: {
                            Label(WatchWorkoutView.label(type), systemImage: WatchWorkoutView.icon(type))
                        }
                    }
                }
            }
            .navigationTitle("快乐轻骑")
        }
    }

    static func durationText(_ t: TimeInterval) -> String {
        let m = Int(t) / 60
        if m >= 60 { return "\(m / 60) 小时 \(m % 60) 分" }
        return "\(m) 分"
    }

    static func distanceText(_ meters: Double) -> String {
        meters >= 1000 ? String(format: "%.1f 公里", meters / 1000) : "\(Int(meters)) 米"
    }
}
