import Foundation

/// 码表「有效骑行时长」状态机（纯逻辑，不依赖 CoreLocation）。
///
/// 计时始终按墙钟推进，只在「停等」时冻结：
/// - 定位有速度且持续低于 `pauseBelowMps` 超过 `pauseAfter` 秒 → 冻结；
/// - 定位**断流**超过 `pauseAfter` 秒也冻结（红灯停住时 iOS 可能干脆不再回调，
///   只靠定位回调驱动的话等红灯会被算成骑行时长）；
/// - 速度回到 `resumeAboveMps` 以上自动续计。
///
/// 起步前（`armed == false`，即还没记录到任何轨迹点）不启用停等，避免出发前静止就冻结。
/// 预热窗口 `warmup` 只在 `start(at:)` 时算一次——不随每次停等恢复重置，
/// 否则市区走走停停会把每次起步后的 8 秒轨迹全部丢掉。
public struct ActiveTimeTracker: Sendable, Equatable {
    public struct Thresholds: Sendable, Equatable {
        public var pauseBelowMps: Double
        public var resumeAboveMps: Double
        public var pauseAfter: TimeInterval
        public var warmup: TimeInterval

        public init(
            pauseBelowMps: Double = 1.0,
            resumeAboveMps: Double = 1.6,
            pauseAfter: TimeInterval = 5,
            warmup: TimeInterval = 8
        ) {
            self.pauseBelowMps = pauseBelowMps
            self.resumeAboveMps = resumeAboveMps
            self.pauseAfter = pauseAfter
            self.warmup = warmup
        }
    }

    public let thresholds: Thresholds

    public private(set) var startDate: Date
    public private(set) var isAutoPaused = false
    public private(set) var isManuallyPaused = false

    private var accumulated: TimeInterval = 0
    private var segmentStart: Date?
    private var warmupDeadline: Date
    private var lowSpeedSince: Date?
    private var lastLocationAt: Date?

    public init(startDate: Date = Date(), thresholds: Thresholds = Thresholds()) {
        self.thresholds = thresholds
        self.startDate = startDate
        self.warmupDeadline = startDate.addingTimeInterval(thresholds.warmup)
        self.segmentStart = startDate
    }

    /// 计时是否正在推进（既没手动暂停也没停等）。
    public var isRunning: Bool { segmentStart != nil }

    /// 到 `date` 为止的有效时长。
    public func activeDuration(at date: Date) -> TimeInterval {
        guard let segmentStart else { return accumulated }
        return accumulated + max(0, date.timeIntervalSince(segmentStart))
    }

    /// GPS 预热是否结束。整段会话只算一次，不随停等恢复重置。
    public func isWarmedUp(at date: Date) -> Bool {
        date >= warmupDeadline
    }

    public mutating func start(at date: Date) {
        startDate = date
        accumulated = 0
        segmentStart = date
        warmupDeadline = date.addingTimeInterval(thresholds.warmup)
        isAutoPaused = false
        isManuallyPaused = false
        lowSpeedSince = nil
        lastLocationAt = nil
    }

    public mutating func manualPause(at date: Date) {
        guard !isManuallyPaused else { return }
        accumulated = activeDuration(at: date)
        segmentStart = nil
        isManuallyPaused = true
        isAutoPaused = false
        lowSpeedSince = nil
        lastLocationAt = nil
    }

    public mutating func manualResume(at date: Date) {
        guard isManuallyPaused else { return }
        isManuallyPaused = false
        isAutoPaused = false
        lowSpeedSince = nil
        lastLocationAt = nil
        segmentStart = date
    }

    /// 收到一个定位。`speedMps` 传调用方能拿到的最好速度（GPS 报速无效时用位移推算）；
    /// `< 0` 表示确实无有效速度——这种定位不算「有速度数据」，交给 `tick` 的断流兜底处理，
    /// 否则手机静止时 GPS 常年报 -1，会一直刷新断流计时让停等永远判不出来。
    /// `armed`：是否已经真正开始移动（已记录轨迹点）；false 时不启用停等。
    public mutating func ingestLocation(timestamp: Date, speedMps: Double, armed: Bool) {
        guard !isManuallyPaused else { return }
        guard speedMps >= 0 else { return }
        lastLocationAt = timestamp
        guard isAutoPaused || armed else { return }

        if isAutoPaused {
            if speedMps >= thresholds.resumeAboveMps {
                isAutoPaused = false
                segmentStart = timestamp
                lowSpeedSince = nil
            }
        } else if speedMps < thresholds.pauseBelowMps {
            if let since = lowSpeedSince {
                if timestamp.timeIntervalSince(since) >= thresholds.pauseAfter {
                    freeze(at: timestamp)
                }
            } else {
                lowSpeedSince = timestamp
            }
        } else {
            lowSpeedSince = nil
        }
    }

    /// 墙钟心跳（UI 每秒调一次）：定位断流超过 `pauseAfter` 秒同样按停等冻结。
    /// 停住不动时 iOS 往往不再送新定位，只靠 `ingestLocation` 永远判不出这次停等。
    public mutating func tick(at date: Date, armed: Bool) {
        guard !isManuallyPaused, !isAutoPaused, armed else { return }
        guard let lastLocationAt else { return }
        guard date.timeIntervalSince(lastLocationAt) >= thresholds.pauseAfter else { return }
        freeze(at: lastLocationAt)
    }

    private mutating func freeze(at date: Date) {
        guard segmentStart != nil else { return }
        accumulated = activeDuration(at: date)
        segmentStart = nil
        isAutoPaused = true
        lowSpeedSince = nil
    }
}
