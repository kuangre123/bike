import Foundation

/// 码表（手动实录）的免费试用额度。
///
/// 被动检测是本 app 的免费主体功能，码表是主动记录，属 Pro。给一次完整的免费试用：
/// **打开时判断能不能用，保存成功才算消耗掉**。
///
/// 顺序很重要。反过来做都不对：
/// - 打开就消耗 —— 误点一下试用就没了；
/// - 保存时才拦 —— 人骑完两小时才被告知要付费，等于骗人骑一趟。
public enum ManualRideTrial {
    /// 非订阅用户可完整用几次。
    public static let freeUses = 1

    /// 现在能不能开码表。
    ///
    /// `usedCount` 来自本地存储，可能是脏数据（负数）或缺失（0）——
    /// 一律按「还没用过」处理：宁可多给一次，也不要凭空判定别人已经用过。
    public static func isAllowed(isPro: Bool, usedCount: Int) -> Bool {
        isPro || remainingFreeUses(usedCount: usedCount) > 0
    }

    /// 还剩几次免费。给 UI 文案用，不会是负数。
    public static func remainingFreeUses(usedCount: Int) -> Int {
        max(0, freeUses - max(0, usedCount))
    }

    /// 消耗一次后的新计数。
    ///
    /// 订阅用户保存时也会走这里，计数会一直涨，所以要防溢出——
    /// 溢出成负数会让退订后反而白得一次免费。
    public static func consuming(_ usedCount: Int) -> Int {
        let current = max(0, usedCount)
        guard current < Int.max else { return Int.max }
        return current + 1
    }
}
