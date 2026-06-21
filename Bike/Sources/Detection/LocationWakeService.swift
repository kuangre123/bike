import Foundation
import CoreLocation

/// 显著位置变化监听 —— 用户开始移动时唤醒被挂起的 App，触发一次对账。
@MainActor
final class LocationWakeService: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()

    /// 收到显著位置变化时回调。
    var onSignificantChange: (() -> Void)?

    override init() {
        super.init()
        manager.delegate = self
    }

    func start() {
        guard CLLocationManager.significantLocationChangeMonitoringAvailable() else { return }
        manager.startMonitoringSignificantLocationChanges()
    }

    func stop() {
        manager.stopMonitoringSignificantLocationChanges()
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        Task { @MainActor [weak self] in
            self?.onSignificantChange?()
        }
    }
}
