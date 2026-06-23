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
            TabView {
                RideTimelineView()
                    .environment(permissions)
                    .environment(coordinator)
                    .tabItem { Label("运动", systemImage: "figure.run") }

                RoutePlannerView()
                    .tabItem { Label("路线", systemImage: "map") }
            }
            .preferredColorScheme(.light)   // UI 为浅色设计（白卡片+浅渐变），锁定浅色避免深色模式白字隐形
            .task {
                #if DEBUG
                // 截图/演示模式：跳过权限请求与后台调度，避免弹窗遮挡 UI
                let env = ProcessInfo.processInfo.environment
                if env["SEED_SAMPLE"] == "1" || env["OPEN_FIRST_DETAIL"] == "1" { return }
                #endif
                coordinator.start()
                BackgroundReconcileTask.schedule()
            }
        }
        .modelContainer(container)
    }
}
