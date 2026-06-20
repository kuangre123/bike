import Foundation

/// 一条心率样本（来自 HealthKit）。
public struct HeartRateSample: Equatable, Sendable {
    public let timestamp: Date
    public let bpm: Double
    public init(timestamp: Date, bpm: Double) {
        self.timestamp = timestamp
        self.bpm = bpm
    }
}

/// 一段「持续心率升高」时段 —— 心率兜底检测出的运动候选。
public struct HRSegment: Equatable, Sendable {
    public let start: Date
    public let end: Date
    public let avgBPM: Double
    public init(start: Date, end: Date, avgBPM: Double) {
        self.start = start
        self.end = end
        self.avgBPM = avgBPM
    }
    public var duration: TimeInterval { end.timeIntervalSince(start) }
}

/// 从心率样本中找出「持续升高」的运动候选段。
/// - 升高阈值 = max(`absoluteFloor`, `restingBPM` × `multiplier`)。
/// - 相邻升高样本间隔 > `maxGap` 视为两段（容忍中途短暂回落）。
/// - 段时长 < `minDuration` 丢弃（滤掉爬楼/情绪等单点尖峰）。
/// - `avgBPM` = 段内升高样本均值。
public func detectElevatedHRSegments(
    from samples: [HeartRateSample],
    restingBPM: Double,
    multiplier: Double = 1.4,
    absoluteFloor: Double = 100,
    minDuration: TimeInterval = 300,
    maxGap: TimeInterval = 180
) -> [HRSegment] {
    let threshold = max(absoluteFloor, restingBPM * multiplier)
    let sorted = samples.sorted { $0.timestamp < $1.timestamp }

    var segments: [HRSegment] = []
    var runStart: Date?
    var runEnd: Date?
    var runSum = 0.0
    var runCount = 0
    var lastElevated: Date?

    func closeRun() {
        if let s = runStart, let e = runEnd, runCount > 0, e.timeIntervalSince(s) >= minDuration {
            segments.append(HRSegment(start: s, end: e, avgBPM: runSum / Double(runCount)))
        }
        runStart = nil; runEnd = nil; runSum = 0; runCount = 0; lastElevated = nil
    }

    for sample in sorted where sample.bpm >= threshold {
        if let last = lastElevated, sample.timestamp.timeIntervalSince(last) > maxGap {
            closeRun()
        }
        if runStart == nil { runStart = sample.timestamp }
        runEnd = sample.timestamp
        runSum += sample.bpm
        runCount += 1
        lastElevated = sample.timestamp
    }
    closeRun()
    return segments
}
