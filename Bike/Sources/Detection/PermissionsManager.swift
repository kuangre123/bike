import Foundation
import CoreMotion
import CoreLocation
import Observation

/// 申请并暴露 运动 + 定位 授权状态。
/// 监听定位授权变化（delegate）即时刷新；运动授权按需 refresh。
@MainActor
@Observable
final class PermissionsManager: NSObject, CLLocationManagerDelegate {
    private let locationManager = CLLocationManager()
    private let activityManager = CMMotionActivityManager()

    private(set) var locationStatus: CLAuthorizationStatus = .notDetermined
    private(set) var motionStatus: CMAuthorizationStatus = CMMotionActivityManager.authorizationStatus()

    override init() {
        super.init()
        locationManager.delegate = self   // 设 delegate 后会回调一次当前授权状态
        locationStatus = locationManager.authorizationStatus
    }

    /// 检测要正常工作，需要「始终」定位 + 运动授权。
    var needsAttention: Bool {
        locationStatus != .authorizedAlways || motionStatus != .authorized
    }

    /// 首页引导横幅是否还要显示。只要定位拿到「使用期间」或「始终」、且运动已授权，就隐藏。
    /// 注意：不要求「始终」——iOS 首次只给「使用期间」，「始终」是后续单独升级的弹窗，
    /// 若按 needsAttention（要求始终）来控制横幅，用户授权完后横幅仍会一直显示。
    var needsSetup: Bool {
        let locOK = locationStatus == .authorizedAlways || locationStatus == .authorizedWhenInUse
        return !locOK || motionStatus != .authorized
    }

    /// 请求「始终」定位（需先 When-In-Use 才能升级，系统分步提示）。
    func requestLocationAlways() {
        locationManager.requestWhenInUseAuthorization()
        locationManager.requestAlwaysAuthorization()
    }

    /// 通过发起一次历史查询触发运动权限提示。
    func requestMotion() {
        guard CMMotionActivityManager.isActivityAvailable() else { return }
        activityManager.queryActivityStarting(
            from: Date().addingTimeInterval(-60), to: Date(), to: .main
        ) { [weak self] _, _ in
            Task { @MainActor in self?.motionStatus = CMMotionActivityManager.authorizationStatus() }
        }
    }

    func requestAll() {
        requestLocationAlways()
        requestMotion()
    }

    /// 重新读取一次当前授权（从设置页返回时调用）。
    func refresh() {
        locationStatus = locationManager.authorizationStatus
        motionStatus = CMMotionActivityManager.authorizationStatus()
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus   // 先取出 Sendable 值，避免把 manager 带过隔离边界
        Task { @MainActor [weak self, status] in
            self?.locationStatus = status
        }
    }
}
