import Foundation

/// 好评引导：只在「价值时刻」请求系统评分弹窗（成熟 App 的克制规则）。
///
/// 门槛（全满足才弹）：记录数 ≥ 5、安装 ≥ 3 天、距上次请求 ≥ 90 天、本版本未请求过。
/// 触发点选在用户刚看到成果的时刻（打开时间线、存完手动骑行、分享完卡片），
/// 绝不在启动页/出错后打断。系统层再兜底：Apple 限一年最多展示 3 次，已评分不再弹。
enum ReviewPrompt {
    static let minRides = 5
    static let minDaysSinceInstall = 3
    static let minDaysBetweenPrompts = 90

    static let installDateKey = "reviewInstallDate"
    static let lastPromptDateKey = "reviewLastPromptDate"
    static let lastPromptVersionKey = "reviewLastPromptVersion"

    /// 纯决策，可单测。`installDate` 为 nil（老用户首次带此功能的版本启动）视为刚开始计天数。
    static func shouldPrompt(
        now: Date,
        installDate: Date?,
        totalRides: Int,
        lastPromptDate: Date?,
        lastPromptedVersion: String?,
        currentVersion: String
    ) -> Bool {
        guard totalRides >= minRides else { return false }
        guard let installDate,
              now.timeIntervalSince(installDate) >= Double(minDaysSinceInstall) * 86400 else { return false }
        if let lastPromptDate,
           now.timeIntervalSince(lastPromptDate) < Double(minDaysBetweenPrompts) * 86400 { return false }
        if lastPromptedVersion == currentVersion { return false }
        return true
    }

    /// 带副作用入口：价值时刻调用。首调补记安装日期（当天起算 3 天门槛）；
    /// 决定弹时记下时间与版本再返回 true，由调用方触发 `requestReview`。
    @MainActor
    static func registerPositiveMomentAndDecide(totalRides: Int, now: Date = Date()) -> Bool {
        let defaults = UserDefaults.standard
        let install = defaults.object(forKey: installDateKey) as? Date
        if install == nil { defaults.set(now, forKey: installDateKey) }

        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
        guard shouldPrompt(
            now: now,
            installDate: install,
            totalRides: totalRides,
            lastPromptDate: defaults.object(forKey: lastPromptDateKey) as? Date,
            lastPromptedVersion: defaults.string(forKey: lastPromptVersionKey),
            currentVersion: version
        ) else { return false }

        defaults.set(now, forKey: lastPromptDateKey)
        defaults.set(version, forKey: lastPromptVersionKey)
        return true
    }
}
