import SwiftUI
import SwiftData

/// 骑行时间线：按自然日分组展示。
struct RideTimelineView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \RideModel.startDate, order: .reverse) private var rides: [RideModel]

    var body: some View {
        NavigationStack {
            Group {
                if rides.isEmpty {
                    ContentUnavailableView(
                        "还没有骑行记录",
                        systemImage: "bicycle",
                        description: Text("骑行会被自动检测并出现在这里。")
                    )
                } else {
                    List {
                        ForEach(groupedByDay, id: \.day) { group in
                            Section(group.day) {
                                ForEach(group.rides) { ride in
                                    RideRowView(ride: ride)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("骑行")
            .toolbar {
                #if DEBUG
                ToolbarItem(placement: .topBarTrailing) {
                    Button("示例", systemImage: "plus", action: addSamples)
                }
                #endif
            }
            #if DEBUG
            // 截图/演示用：以环境变量 SEED_SAMPLE=1 启动时自动注入示例数据。
            .onAppear {
                if ProcessInfo.processInfo.environment["SEED_SAMPLE"] == "1", rides.isEmpty {
                    addSamples()
                }
            }
            #endif
        }
    }

    /// 按自然日分组；日组按日期倒序，组内沿用 @Query 的开始时间倒序。
    private var groupedByDay: [(day: String, rides: [RideModel])] {
        let cal = Calendar.current
        let groups = Dictionary(grouping: rides) { cal.startOfDay(for: $0.startDate) }
        return groups
            .sorted { $0.key > $1.key }
            .map { (day: Formatters.dayHeader($0.key), rides: $0.value) }
    }

    #if DEBUG
    private func addSamples() {
        let store = RideStore(context: context)
        try? store.save(SampleData.rides())
    }
    #endif
}
