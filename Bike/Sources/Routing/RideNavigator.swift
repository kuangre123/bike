import Foundation
import CoreLocation
import AVFoundation
import CyclingDomain
import Observation

/// 导航运行时：定位 → navigationProgress → 更新转向卡、语音、偏航重算。
@MainActor
@Observable
final class RideNavigator: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private let speech = AVSpeechSynthesizer()
    private let service = RouteService()

    private(set) var coords: [GeoCoordinate]
    private(set) var turns: [TurnInstruction]
    private(set) var progress: NavProgress?
    private(set) var arrived = false
    private let destination: GeoCoordinate
    private var lastSpokenTurnIndex: Int?
    private var offRouteSince: Date?
    private var rerouting = false

    var voiceEnabled = true

    init(plan: RoutePlan, destination: GeoCoordinate) {
        self.coords = plan.coordinates
        self.turns = turnsFromPolyline(plan.coordinates)
        self.destination = destination
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
    }

    func start() {
        manager.requestWhenInUseAuthorization()
        manager.startUpdatingLocation()
    }

    func stop() {
        manager.stopUpdatingLocation()
    }

    private func handle(_ loc: GeoCoordinate) {
        guard coords.count >= 2 else { return }
        let p = navigationProgress(location: loc, coords: coords, turns: turns)
        progress = p

        if let next = p.nextTurn, next.direction == .arrive, p.distanceToNextTurnMeters < 25 {
            arrived = true
            speak("已到达目的地")
            stop()
            return
        }
        if let next = p.nextTurn, next.direction != .arrive,
           p.distanceToNextTurnMeters < 150, lastSpokenTurnIndex != next.coordinateIndex {
            lastSpokenTurnIndex = next.coordinateIndex
            speak("前方 \(Int(p.distanceToNextTurnMeters)) 米，\(phrase(next.direction))")
        }
        if p.isOffRoute {
            if offRouteSince == nil { offRouteSince = Date() }
            if let since = offRouteSince, Date().timeIntervalSince(since) > 8, !rerouting {
                Task { await reroute(from: loc) }
            }
        } else {
            offRouteSince = nil
        }
    }

    private func reroute(from loc: GeoCoordinate) async {
        rerouting = true
        defer { rerouting = false }
        if case .success(let plan) = await service.route(from: loc, to: destination) {
            coords = plan.coordinates
            turns = turnsFromPolyline(plan.coordinates)
            lastSpokenTurnIndex = nil
            offRouteSince = nil
            speak("已重新规划路线")
        }
    }

    private func speak(_ text: String) {
        guard voiceEnabled else { return }
        let u = AVSpeechUtterance(string: text)
        u.voice = AVSpeechSynthesisVoice(language: "zh-CN")
        speech.speak(u)
    }

    private func phrase(_ d: TurnDirection) -> String {
        switch d {
        case .left, .slightLeft: return "向左"
        case .sharpLeft: return "向左急转"
        case .right, .slightRight: return "向右"
        case .sharpRight: return "向右急转"
        case .uTurn: return "掉头"
        case .straight: return "直行"
        case .arrive: return "到达"
        }
    }

    nonisolated func locationManager(_ m: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let last = locations.last else { return }
        let c = GeoCoordinate(latitude: last.coordinate.latitude, longitude: last.coordinate.longitude)
        Task { @MainActor in self.handle(c) }
    }
}
