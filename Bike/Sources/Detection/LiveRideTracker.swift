import Foundation
import CoreLocation
import CyclingDomain

/// 骑行进行时的全功率 GPS 采集 —— 检测的「增强层」。
/// 确认骑行后 `start`，骑行停止时 `stop` 产出一条 `TrackedRide`。
@MainActor
final class LiveRideTracker: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private var samples: [GPSSample] = []
    private var startDate: Date?
    private var onFinish: ((TrackedRide) -> Void)?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.activityType = .fitness
        manager.allowsBackgroundLocationUpdates = true
        manager.pausesLocationUpdatesAutomatically = false
    }

    var isRunning: Bool { startDate != nil }

    func start(onFinish: @escaping (TrackedRide) -> Void) {
        guard startDate == nil else { return }
        self.onFinish = onFinish
        samples = []
        startDate = Date()
        manager.startUpdatingLocation()
    }

    func stop() {
        guard let start = startDate else { return }
        manager.stopUpdatingLocation()
        let ride = TrackedRide(start: start, end: Date(), samples: samples)
        startDate = nil
        let callback = onFinish
        onFinish = nil
        callback?(ride)
    }

    // CL 在主线程回调（manager 在主线程创建）；映射为 Sendable 后跨界。
    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let mapped = locations.map { loc in
            GPSSample(
                timestamp: loc.timestamp,
                latitude: loc.coordinate.latitude,
                longitude: loc.coordinate.longitude,
                speedMps: max(0, loc.speed)
            )
        }
        MainActor.assumeIsolated {
            samples.append(contentsOf: mapped)
        }
    }
}
