import SwiftUI
import SwiftData

@main
struct BikeApp: App {
    private let container: ModelContainer
    @State private var permissions: PermissionsManager
    @State private var coordinator: RideDetectionCoordinator

    init() {
        let container: ModelContainer
        do {
            container = try ModelContainer(for: RideModel.self)
        } catch {
            fatalError("无法初始化 SwiftData ModelContainer: \(error)")
        }
        self.container = container

        let perms = PermissionsManager()
        let coord = RideDetectionCoordinator(container: container, permissions: perms)
        _permissions = State(initialValue: perms)
        _coordinator = State(initialValue: coord)

        BackgroundReconcileTask.register(coordinator: coord)
    }

    var body: some Scene {
        WindowGroup {
            RideTimelineView()
                .environment(permissions)
                .environment(coordinator)
                .task {
                    coordinator.start()
                    BackgroundReconcileTask.schedule()
                }
        }
        .modelContainer(container)
    }
}
