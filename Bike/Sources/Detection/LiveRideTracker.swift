import Foundation
import CoreLocation
import CyclingDomain

/// 运动进行时的全功率 GPS 采集 —— 检测的「增强层」。
/// 确认运动后 `start(activityType:)`，停止时 `stop` 产出一条 `TrackedRide`。
@MainActor
final class LiveRideTracker: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private var samples: [GPSSample] = []
    private var startDate: Date?
    private var activityType: ActivityType?
    private var onFinish: ((TrackedRide) -> Void)?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.activityType = .fitness
    }

    var isRunning: Bool { startDate != nil }

    func start(activityType: ActivityType, onFinish: @escaping (TrackedRide) -> Void) {
        guard startDate == nil else { return }
        self.activityType = activityType
        self.onFinish = onFinish
        samples = []
        startDate = Date()
        // 只在真正开始追踪时开后台更新（未授权时在 init 设置会触发权限请求）
        manager.allowsBackgroundLocationUpdates = true
        manager.pausesLocationUpdatesAutomatically = false
        manager.startUpdatingLocation()
    }

    func stop() {
        guard let start = startDate else { return }
        manager.stopUpdatingLocation()
        let ride = TrackedRide(
            activityType: activityType ?? .cycling,
            start: start, end: Date(), samples: samples
        )
        startDate = nil
        activityType = nil
        let callback = onFinish
        onFinish = nil
        callback?(ride)
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let mapped = locations.map { loc in
            GPSSample(
                timestamp: loc.timestamp,
                latitude: loc.coordinate.latitude,
                longitude: loc.coordinate.longitude,
                speedMps: max(0, loc.speed)
            )
        }
        Task { @MainActor [weak self, mapped] in
            self?.samples.append(contentsOf: mapped)
        }
    }
}
