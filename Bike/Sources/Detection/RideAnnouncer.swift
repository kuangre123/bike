import Foundation
import AVFoundation
import CyclingDomain

/// 骑行中的语音报时：每满 10 分钟 / 每满 5 公里念一次时长、距离、均速。
///
/// 音频会话用 `.duckOthers`：把正在放的音乐 / 播客压低而不是掐断，念完自动恢复。
/// 每次播报前后各激活 / 释放一次，避免整段骑行都占着音频会话把别的 app 压住。
@MainActor
final class RideAnnouncer: NSObject {
    /// 关掉时连音频会话都不碰。
    var isEnabled: Bool

    private let synthesizer = AVSpeechSynthesizer()
    private var tracker: AnnouncementTracker

    init(isEnabled: Bool = true, tracker: AnnouncementTracker = AnnouncementTracker()) {
        self.isEnabled = isEnabled
        self.tracker = tracker
        super.init()
        synthesizer.delegate = self
    }

    /// 喂进当前进度；到里程碑就念一句。返回是否真的播报了（便于测试 / 调试）。
    @discardableResult
    func update(durationSeconds: TimeInterval, distanceMeters: Double?) -> Bool {
        guard isEnabled else { return false }
        guard let announcement = tracker.advance(
            durationSeconds: durationSeconds, distanceMeters: distanceMeters) else { return false }
        speak(Self.text(for: announcement))
        return true
    }

    /// 骑行结束时收尾：停掉未念完的，交还音频会话。
    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
        deactivateSession()
    }

    /// 播报文案。
    ///
    /// 三种整句而不是拿分隔符拼接：拼接对翻译不友好（标点、语序都不一样），
    /// 整句让译者能按各自语言组织。没有距离就只念时长，不念「0 公里、平均时速 0」冒充有数据。
    static func text(for announcement: RideAnnouncement) -> String {
        let duration = Formatters.duration(announcement.durationSeconds)
        guard let distanceMeters = announcement.distanceMeters else {
            return String(localized: "已骑行 \(duration)")
        }
        let distance = Formatters.distance(distanceMeters)
        guard let speedMps = announcement.avgSpeedMps else {
            return String(localized: "已骑行 \(duration)，\(distance)")
        }
        return String(localized: "已骑行 \(duration)，\(distance)，平均时速 \(Formatters.speed(speedMps))")
    }

    /// 念完就把音频会话还回去，否则整段骑行音乐都被压着。
    private func finishedSpeaking() {
        guard !synthesizer.isSpeaking else { return }
        deactivateSession()
    }

    private func speak(_ text: String) {
        activateSession()
        let utterance = AVSpeechUtterance(string: text)
        // 跟随系统语言，和界面文案保持一致
        utterance.voice = AVSpeechSynthesisVoice(language: Locale.preferredLanguages.first)
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        synthesizer.speak(utterance)
    }

    private func activateSession() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(
                .playback, mode: .voicePrompt,
                options: [.duckOthers, .interruptSpokenAudioAndMixWithOthers])
            try session.setActive(true)
        } catch {
            // 音频会话拿不到就不念，不影响骑行记录本身。
        }
    }

    private func deactivateSession() {
        try? AVAudioSession.sharedInstance()
            .setActive(false, options: .notifyOthersOnDeactivation)
    }
}


extension RideAnnouncer: AVSpeechSynthesizerDelegate {
    nonisolated func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance
    ) {
        Task { @MainActor in self.finishedSpeaking() }
    }

    nonisolated func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance
    ) {
        Task { @MainActor in self.finishedSpeaking() }
    }
}
