import SwiftUI
import SwiftData

/// 运动时间线：本周概览 + 按自然日分组；点进单次看详情，滑动删除（撤销自动添加）。
struct RideTimelineView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \RideModel.startDate, order: .reverse) private var rides: [RideModel]
    @State private var showingSettings = false
    @State private var path = NavigationPath()

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if rides.isEmpty {
                    ContentUnavailableView(
                        "还没有运动记录",
                        systemImage: "figure.run",
                        description: Text("步行、跑步、骑行会被自动检测并出现在这里。")
                    )
                } else {
                    List {
                        Section("本周") {
                            StatsSummaryView(rides: rides)
                        }
                        ForEach(groupedByDay, id: \.day) { group in
                            Section(group.day) {
                                ForEach(group.rides) { ride in
                                    NavigationLink(value: ride) {
                                        RideRowView(ride: ride)
                                    }
                                    .swipeActions(edge: .trailing) {
                                        Button("删除", role: .destructive) {
                                            context.delete(ride)
                                            try? context.save()
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("运动")
            .navigationDestination(for: RideModel.self) { ride in
                RideDetailView(ride: ride)
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("设置", systemImage: "gearshape") { showingSettings = true }
                }
                #if DEBUG
                ToolbarItem(placement: .topBarTrailing) {
                    Button("示例", systemImage: "plus", action: addSamples)
                }
                #endif
            }
            .sheet(isPresented: $showingSettings) {
                SettingsView()
            }
            #if DEBUG
            .onAppear {
                if ProcessInfo.processInfo.environment["SEED_SAMPLE"] == "1", rides.isEmpty {
                    addSamples()
                }
                // 深链：直接打开第一条详情（截图地图用）
                if ProcessInfo.processInfo.environment["OPEN_FIRST_DETAIL"] == "1",
                   path.isEmpty, let first = rides.first(where: { $0.routeData != nil }) ?? rides.first {
                    path.append(first)
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
        try? store.save(SampleData.rides(), autoDetected: false)
    }
    #endif
}
