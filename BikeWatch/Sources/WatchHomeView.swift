import SwiftUI
import CyclingDomain

/// 手表首页：选运动类型开始记录（采心率）。今日概览（手机同步）在 step B 接入。
struct WatchHomeView: View {
    private let types: [ActivityType] = [.cycling, .running, .walking, .other]

    var body: some View {
        NavigationStack {
            List {
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
}
