import SwiftUI

@main
struct BikeWatchApp: App {
    @State private var connectivity = WatchConnectivityProvider()

    var body: some Scene {
        WindowGroup {
            WatchHomeView()
                .environment(connectivity)
        }
    }
}
