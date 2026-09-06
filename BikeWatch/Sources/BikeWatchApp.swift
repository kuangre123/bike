import SwiftUI
import CyclingDomain

@main
struct BikeWatchApp: App {
    @State private var connectivity = WatchConnectivityProvider()
    @State private var heartRate = WatchHeartRateMonitor()

    var body: some Scene {
        WindowGroup {
            #if DEBUG
            if let raw = ProcessInfo.processInfo.environment["WATCH_WORKOUT"],
               let type = ActivityType(rawValue: raw) {
                NavigationStack { WatchWorkoutView(activityType: type) }
                    .environment(heartRate)
            } else {
                home
            }
            #else
            home
            #endif
        }
    }

    private var home: some View {
        WatchHomeView()
            .environment(connectivity)
            .environment(heartRate)
            .task {
                // 心率一测到就推给手机——手机自己读 HealthKit 要等系统后台回写，慢几十秒到几分钟。
                heartRate.onReading = { [connectivity] reading in
                    connectivity.send(heartRate: reading)
                }
                // 只在已授权时静默开始；没授权过就不在首页弹窗，等用户点卡片。
                await heartRate.startIfAuthorized()
            }
    }
}
