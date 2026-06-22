import SwiftUI
import CyclingDomain

@main
struct BikeWatchApp: App {
    @State private var connectivity = WatchConnectivityProvider()

    var body: some Scene {
        WindowGroup {
            #if DEBUG
            if let raw = ProcessInfo.processInfo.environment["WATCH_WORKOUT"],
               let type = ActivityType(rawValue: raw) {
                NavigationStack { WatchWorkoutView(activityType: type) }
            } else {
                WatchHomeView().environment(connectivity)
            }
            #else
            WatchHomeView().environment(connectivity)
            #endif
        }
    }
}
