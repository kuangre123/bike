import Foundation
import CoreLocation
import AVFoundation
import CyclingDomain
import Observation

/// 导航运行时：定位 → navigationProgress → 更新转向卡、语音、偏航重算。
@MainActor
@Observable
final class RideNavigator: NSObject, CLLocationManagerDelegate, AVSpeechSynthesizerDelegate {
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
        // 优先算路引擎的转向（只在真正的路口发提示），引擎没给才几何推导。
        self.turns = plan.navigationTurns
        self.destination = destination
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        speech.delegate = self
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
            speak(String(localized: "已到达目的地"))
            stop()
            return
        }
        if let next = p.nextTurn, next.direction != .arrive,
           p.distanceToNextTurnMeters < 150, lastSpokenTurnIndex != next.coordinateIndex {
            lastSpokenTurnIndex = next.coordinateIndex
            speak(String(localized: "前方 \(Int(p.distanceToNextTurnMeters)) 米，\(Formatters.turnPhrase(next))"))
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
        if case .success(let plan) = await service.route(from: loc, to: destination, profile: RoutePrefs.profile) {
            coords = plan.coordinates
            turns = plan.navigationTurns
            lastSpokenTurnIndex = nil
            offRouteSince = nil
            speak(String(localized: "已重新规划路线"))
        }
    }

    private func speak(_ text: String) {
        guard voiceEnabled else { return }
        activateAudioSession()
        let u = AVSpeechUtterance(string: text)
        // 跟随系统语言。以前写死 zh-CN：德语用户会听到中文口音念德语文案。
        u.voice = AVSpeechSynthesisVoice(language: Locale.preferredLanguages.first)
        speech.speak(u)
    }

    /// 导航播报：用 .playback + .voicePrompt，静音开关下也出声、并压低背景音乐。
    private func activateAudioSession() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(
            .playback, mode: .voicePrompt,
            options: [.duckOthers, .interruptSpokenAudioAndMixWithOthers])
        try? session.setActive(true)
    }

    /// 播报全部结束后释放音频会话，让背景音乐恢复原音量。
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in
            guard !self.speech.isSpeaking else { return }
            try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
        }
    }


    nonisolated func locationManager(_ m: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let last = locations.last else { return }
        let c = GeoCoordinate(latitude: last.coordinate.latitude, longitude: last.coordinate.longitude)
        Task { @MainActor in self.handle(c) }
    }
}
