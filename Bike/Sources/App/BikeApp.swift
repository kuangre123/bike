import SwiftUI
import SwiftData

@main
struct BikeApp: App {
    var body: some Scene {
        WindowGroup {
            RideTimelineView()
        }
        .modelContainer(for: RideModel.self)
    }
}
