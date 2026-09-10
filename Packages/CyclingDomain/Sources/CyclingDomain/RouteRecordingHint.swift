import Foundation

/// 判断「该不该提示用户把定位改成始终」时，一条记录需要的信息。
public struct RoutelessRideSample: Sendable, Equatable {
    public let isAutoDetected: Bool
    public let hasRoute: Bool
    public let end: Date

    public init(isAutoDetected: Bool, hasRoute: Bool, end: Date) {
        self.isAutoDetected = isAutoDetected
        self.hasRoute = hasRoute
        self.end = end
    }
}

/// 首页提示：最近多次骑行都没能记录路线时，告诉用户原因是定位不是「始终」。
///
/// 后台采轨迹只有「始终」定位才行，但「使用期间」也能让权限横幅消失，
/// 于是会静默降级——骑行照样检测到，却永远没有轨迹。
///
/// **有证据才提示**：不是一装上就催权限，而是等这件事真的发生过几次。
/// 这样既不骚扰新用户，也不会让老用户一直被无关的横幅挡着。
public enum RouteRecordingHint {
    /// 攒够几条才提示。
    public static let minimumRoutelessRides = 3

    /// 只看最近这段时间。更早的记录可能是授权之前的，现在早就好了，不能当作当前证据。
    public static let lookback: TimeInterval = 30 * 24 * 3600

    /// 最近窗口内「自动检测到但没有轨迹」的骑行数量。
    ///
    /// 只数自动检测的：手动码表是前台运行的，它缺轨迹另有原因（比如定位整个关掉了），
    /// 拿来当「该开始终定位」的证据会指错方向。
    public static func routelessCount(_ rides: [RoutelessRideSample], now: Date) -> Int {
        rides.filter { ride in
            guard ride.isAutoDetected, !ride.hasRoute else { return false }
            // 未来时间戳（时钟漂移）也算在窗口内，不因为一个坏时间戳就漏掉证据
            return now.timeIntervalSince(ride.end) <= lookback
        }.count
    }

    /// 是否显示提示卡片。
    public static func shouldPrompt(
        routelessCount: Int,
        hasAlwaysLocation: Bool,
        dismissed: Bool
    ) -> Bool {
        guard !dismissed, !hasAlwaysLocation else { return false }
        return routelessCount >= minimumRoutelessRides
    }
}
