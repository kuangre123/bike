import Foundation
import CoreMotion
import CoreLocation
import Observation

/// 申请并暴露 运动 + 定位 授权状态。
/// 状态用计算属性按需读取（M3 不做实时观察刷新；重开设置页即刷新）。
@MainActor
@Observable
final class PermissionsManager {
    private let locationManager = CLLocationManager()
    private let activityManager = CMMotionActivityManager()
    private let probeQueue = OperationQueue()

    var locationStatus: CLAuthorizationStatus { locationManager.authorizationStatus }
    var motionStatus: CMAuthorizationStatus { CMMotionActivityManager.authorizationStatus() }

    /// 请求「始终」定位（需先有 When-In-Use 才能升级，系统会分步提示）。
    func requestLocationAlways() {
        locationManager.requestWhenInUseAuthorization()
        locationManager.requestAlwaysAuthorization()
    }

    /// 通过发起一次历史查询来触发运动权限提示。
    func requestMotion() {
        guard CMMotionActivityManager.isActivityAvailable() else { return }
        activityManager.queryActivityStarting(
            from: Date().addingTimeInterval(-60), to: Date(), to: probeQueue
        ) { _, _ in }
    }

    func requestAll() {
        requestLocationAlways()
        requestMotion()
    }
}
